/*
 * Native side of the nokogiri spin package, over libxml2 2.13.9 with
 * Nokogiri 1.19.4's six patches -- the libxml2 Nokogiri itself packages --
 * carried in libxml2/ (headers in libxml/, so `#include <libxml/...>`
 * resolves through spin's `-I <package>`).
 *
 * A Nokogiri node holds a `native_struct` (NokoNodeRef): one xmlNode plus
 * the OWNER of its document. libxml2 frees a document with every node in
 * its tree; a node that was unlinked (replaced, removed) is no longer in
 * the tree and would leak -- or, freed eagerly, leave a live Ruby handle
 * pointing at freed memory. Nokogiri's rule, kept here: an unlinked node
 * is listed with its document and freed when the document is, if it is
 * still parentless then. The owner counts every handle; the last one to
 * go frees the document and its listed pieces. Owner bookkeeping is under
 * one mutex, because finalizers may run on a GC sweeper thread.
 *
 * Serialization is Nokogiri's: `to_html` is xmlSaveTree through a save
 * context with SaveOptions::DEFAULT_HTML (FORMAT | NO_DECLARATION |
 * NO_EMPTY_TAGS | AS_HTML) and the document's encoding.
 *
 * Markup arrives as a Spinel String, and its length is the string's own
 * (sp_str_byte_len), as Nokogiri reads RSTRING_LEN: an embedded NUL reaches
 * the parser -- gumbo turns it into U+FFFD -- instead of ending the input.
 */

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <libxml/HTMLparser.h>
#include <libxml/parser.h>
#include <libxml/HTMLtree.h>
#include <libxml/entities.h>
#include <libxml/tree.h>
#include <libxml/xmlsave.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>

#include "spinel/runtime.h" /* sp_gc_alloc, sp_int, sp_bool, sp_RbVal */

#include "gumbo/nokogiri_gumbo.h"

/* ---- owners ------------------------------------------------------------ */

/* A parse's errors, as Nokogiri collects them: every structured error
   libxml2 reports while the document is read, in order. */
typedef struct sp_nk_err {
	int level, line, column;
	char *message;
} sp_nk_err;

typedef struct sp_nk_errs {
	sp_nk_err *v;
	size_t n, cap;
} sp_nk_errs;

typedef struct sp_nk_owner {
	long refs;
	xmlDocPtr doc;
	xmlNodePtr *pieces;
	size_t n, cap;
	sp_nk_errs errs;
	/* Namespace definitions remove_namespaces! took off their elements:
	   Nokogiri keeps them alive with the document, since a node's ns may
	   still name one, and so does this. */
	xmlNsPtr removed_ns;
	/* An HTML5 document (parsed by gumbo, serialized by the HTML5
	   rules) and its quirks mode; -1 when it is not one. */
	int html5;
	int quirks_mode;
} sp_nk_owner;

static pthread_mutex_t sp_nk_lock = PTHREAD_MUTEX_INITIALIZER;
static long sp_nk_live_docs = 0;

sp_int sp_noko_live_documents(void)
{
	return (sp_int)__atomic_load_n(&sp_nk_live_docs, __ATOMIC_RELAXED);
}

/* Callers hold sp_nk_lock. */
static void sp_nk_list(sp_nk_owner *o, xmlNodePtr node)
{
	size_t i;
	for (i = 0; i < o->n; i++)
		if (o->pieces[i] == node)
			return;
	if (o->n == o->cap) {
		o->cap = o->cap ? o->cap * 2 : 8;
		o->pieces = (xmlNodePtr *)realloc(o->pieces, o->cap * sizeof(xmlNodePtr));
	}
	o->pieces[o->n++] = node;
}

/* Callers hold sp_nk_lock. Decide every piece's fate before freeing any:
   a listed node that was put back into the tree (or into another listed
   piece) goes with that tree, and asking it for its parent after the tree
   was freed would read freed memory. */
static void sp_nk_errs_free(sp_nk_errs *e)
{
	size_t i;
	for (i = 0; i < e->n; i++)
		free(e->v[i].message);
	free(e->v);
	e->v = NULL;
	e->n = e->cap = 0;
}

static void sp_nk_release_locked(sp_nk_owner *o)
{
	size_t i, k = 0;
	if (--o->refs > 0)
		return;
	for (i = 0; i < o->n; i++)
		if (o->pieces[i]->parent == NULL)
			o->pieces[k++] = o->pieces[i];
	for (i = 0; i < k; i++)
		xmlFreeNode(o->pieces[i]);
	xmlFreeDoc(o->doc);
	if (o->removed_ns)
		xmlFreeNsList(o->removed_ns);
	sp_nk_errs_free(&o->errs);
	free(o->pieces);
	free(o);
	__atomic_sub_fetch(&sp_nk_live_docs, 1, __ATOMIC_RELAXED);
}

/* ---- the node handle --------------------------------------------------- */

typedef struct sp_NokoNode_s {
	sp_int cls_id;
	xmlNodePtr node;
	sp_nk_owner *owner;
} sp_NokoNode;

void sp_NokoNode_fin(void *p)
{
	sp_NokoNode *s = (sp_NokoNode *)p;
	if (s && s->owner) {
		pthread_mutex_lock(&sp_nk_lock);
		sp_nk_release_locked(s->owner);
		pthread_mutex_unlock(&sp_nk_lock);
		s->owner = NULL;
		s->node = NULL;
	}
}

sp_NokoNode *sp_NokoNode_new(sp_int cls_id)
{
	sp_NokoNode *s = (sp_NokoNode *)sp_gc_alloc(sizeof(sp_NokoNode), sp_NokoNode_fin, NULL);
	s->cls_id = cls_id;
	s->node = NULL;
	s->owner = NULL;
	return s;
}

static sp_NokoNode *sp_nk_wrap(sp_int cls_id, xmlNodePtr node, sp_nk_owner *owner)
{
	sp_NokoNode *s = sp_NokoNode_new(cls_id);
	if (node && owner) {
		pthread_mutex_lock(&sp_nk_lock);
		owner->refs++;
		pthread_mutex_unlock(&sp_nk_lock);
		s->node = node;
		s->owner = owner;
	}
	return s;
}

/* A node argument arrives boxed (spec :any). */
static sp_NokoNode *sp_nk_arg(sp_RbVal v)
{
	return (sp_NokoNode *)v.v.p;
}

sp_bool sp_NokoNode_present_p(sp_NokoNode *self)
{
	return self->node != NULL;
}

sp_bool sp_NokoNode_same_p(sp_NokoNode *self, sp_RbVal other)
{
	return self->node == sp_nk_arg(other)->node;
}

/* ---- parsing ----------------------------------------------------------- */

/* The errors of the parse in progress, per thread, as Nokogiri's
   structured error handler collects them; a parse that answers a document
   hands them to its owner, and one that fails (strict mode) leaves them
   here for the SyntaxError the Ruby side raises. */
static SP_TLS sp_nk_errs sp_nk_parse_errs = {NULL, 0, 0};

static void sp_nk_collect(void *ctx, const xmlError *err)
{
	sp_nk_errs *e = &sp_nk_parse_errs;
	size_t len;
	char *msg;
	(void)ctx;
	if (e->n == e->cap) {
		e->cap = e->cap ? e->cap * 2 : 8;
		e->v = (sp_nk_err *)realloc(e->v, e->cap * sizeof(sp_nk_err));
	}
	msg = strdup(err->message ? err->message : "");
	len = strlen(msg);
	while (len > 0 && msg[len - 1] == '\n')
		msg[--len] = '\0';
	e->v[e->n].level = (int)err->level;
	e->v[e->n].line = err->line;
	e->v[e->n].column = err->int2;
	e->v[e->n].message = msg;
	e->n++;
}

static void sp_nk_begin_parse(void)
{
	sp_nk_errs_free(&sp_nk_parse_errs);
	xmlResetLastError();
	xmlSetStructuredErrorFunc(NULL, sp_nk_collect);
}

static sp_NokoNode *sp_nk_own(sp_int cls_id, xmlDocPtr doc)
{
	sp_nk_owner *o = (sp_nk_owner *)calloc(1, sizeof(sp_nk_owner));
	o->doc = doc;
	o->errs = sp_nk_parse_errs;
	o->quirks_mode = -1;
	sp_nk_parse_errs.v = NULL;
	sp_nk_parse_errs.n = sp_nk_parse_errs.cap = 0;
	__atomic_add_fetch(&sp_nk_live_docs, 1, __ATOMIC_RELAXED);
	return sp_nk_wrap(cls_id, (xmlNodePtr)doc, o);
}

/* Nokogiri::HTML4::Document.parse(string): htmlReadMemory with the String's
   encoding (UTF-8) and ParseOptions::DEFAULT_HTML. An empty or unparseable
   string still answers a document, as it does in Nokogiri. */
sp_NokoNode *sp_NokoNode_parse_html(sp_NokoNode *self, const char *html, const char *encoding, sp_int options)
{
	htmlDocPtr doc;
	sp_nk_begin_parse();
	doc = htmlReadMemory(html, (int)sp_str_byte_len(html), NULL, encoding, (int)options);
	xmlSetStructuredErrorFunc(NULL, NULL);
	if (!doc)
		doc = htmlNewDocNoDtD(NULL, NULL);
	return sp_nk_own(self->cls_id, doc);
}

/* Nokogiri::XML::Document.parse(string, url, encoding, options): the gem's
   read_memory -- xmlReadMemory, with no encoding unless one is named (the
   declaration decides). Without RECOVER a malformed document answers no
   document: the handle is empty and the errors stay for the raise. */
sp_NokoNode *sp_NokoNode_parse_xml(sp_NokoNode *self, const char *xml, const char *encoding, sp_int options)
{
	xmlDocPtr doc;
	sp_nk_begin_parse();
	doc = xmlReadMemory(xml, (int)sp_str_byte_len(xml), NULL, *encoding ? encoding : NULL, (int)options);
	xmlSetStructuredErrorFunc(NULL, NULL);
	if (!doc)
		return sp_NokoNode_new(self->cls_id);
	return sp_nk_own(self->cls_id, doc);
}

/* Nokogiri::XML::Document.new: an empty version-1.0 document (what the gem
   answers for an empty string). */
sp_NokoNode *sp_NokoNode_new_xml_document(sp_NokoNode *self)
{
	sp_nk_begin_parse();
	return sp_nk_own(self->cls_id, xmlNewDoc((const xmlChar *)"1.0"));
}

/* A document's errors (a parse's, when the parse answered none). */
static sp_nk_errs *sp_nk_errs_of(sp_NokoNode *self)
{
	return self->owner ? &self->owner->errs : &sp_nk_parse_errs;
}

sp_int sp_NokoNode_error_count(sp_NokoNode *self)
{
	return (sp_int)sp_nk_errs_of(self)->n;
}

sp_int sp_NokoNode_error_level(sp_NokoNode *self, sp_int i)
{
	return sp_nk_errs_of(self)->v[i].level;
}

sp_int sp_NokoNode_error_line(sp_NokoNode *self, sp_int i)
{
	return sp_nk_errs_of(self)->v[i].line;
}

sp_int sp_NokoNode_error_column(sp_NokoNode *self, sp_int i)
{
	return sp_nk_errs_of(self)->v[i].column;
}

const char *sp_NokoNode_error_message(sp_NokoNode *self, sp_int i)
{
	return sp_nk_errs_of(self)->v[i].message;
}

/* ---- reading ----------------------------------------------------------- */

sp_int sp_NokoNode_type(sp_NokoNode *self)
{
	return (sp_int)self->node->type;
}

const char *sp_NokoNode_name(sp_NokoNode *self)
{
	if (self->node->type == XML_DOCUMENT_NODE || self->node->type == XML_HTML_DOCUMENT_NODE)
		return "document";
	return self->node->name ? (const char *)self->node->name : "";
}

sp_NokoNode *sp_NokoNode_first_child(sp_NokoNode *self)
{
	return sp_nk_wrap(self->cls_id, self->node->children, self->owner);
}

sp_NokoNode *sp_NokoNode_last_child(sp_NokoNode *self)
{
	return sp_nk_wrap(self->cls_id, self->node->last, self->owner);
}

sp_NokoNode *sp_NokoNode_next_sibling(sp_NokoNode *self)
{
	return sp_nk_wrap(self->cls_id, self->node->next, self->owner);
}

sp_NokoNode *sp_NokoNode_previous_sibling(sp_NokoNode *self)
{
	return sp_nk_wrap(self->cls_id, self->node->prev, self->owner);
}

sp_NokoNode *sp_NokoNode_parent(sp_NokoNode *self)
{
	return sp_nk_wrap(self->cls_id, self->node->parent, self->owner);
}

sp_NokoNode *sp_NokoNode_document(sp_NokoNode *self)
{
	return sp_nk_wrap(self->cls_id, (xmlNodePtr)self->owner->doc, self->owner);
}

/* Text results come back through one per-thread buffer the FFI copies out
   at the boundary. */
static SP_TLS char *sp_nk_out = NULL;

static const char *sp_nk_set_out(xmlChar *s)
{
	free(sp_nk_out);
	sp_nk_out = s ? strdup((const char *)s) : strdup("");
	if (s)
		xmlFree(s);
	return sp_nk_out;
}

const char *sp_noko_out(void)
{
	return sp_nk_out ? sp_nk_out : "";
}

/* Node#content / #text: xmlNodeGetContent. */
sp_int sp_NokoNode_content(sp_NokoNode *self)
{
	return (sp_int)strlen(sp_nk_set_out(xmlNodeGetContent(self->node)));
}

/* Attributes. `has` distinguishes a missing attribute (Nokogiri answers
   nil) from an empty one. */
sp_bool sp_NokoNode_has_attr(sp_NokoNode *self, const char *name)
{
	return self->node->type == XML_ELEMENT_NODE && xmlHasProp(self->node, (const xmlChar *)name) != NULL;
}

/* Node#[](name), the gem's `get`: an unprefixed name is an attribute in
   no namespace (so "href" does not find xlink:href); "prefix:name" is
   looked up in the namespace that prefix is bound to here, and as the
   literal name when it is bound to none. -1 when there is no such
   attribute. */
sp_int sp_NokoNode_attr(sp_NokoNode *self, const char *name)
{
	xmlNodePtr node = self->node;
	xmlChar *value = NULL;
	const char *colon;

	if (node->type != XML_ELEMENT_NODE)
		return -1;
	colon = strchr(name, ':');
	if (colon) {
		xmlChar *prefix = xmlStrndup((const xmlChar *)name, (int)(colon - name));
		xmlNsPtr ns = xmlSearchNs(node->doc, node, prefix);
		xmlFree(prefix);
		value = ns ? xmlGetNsProp(node, (const xmlChar *)(colon + 1), ns->href)
		           : xmlGetProp(node, (const xmlChar *)name);
	} else {
		value = xmlGetNoNsProp(node, (const xmlChar *)name);
	}
	if (!value)
		return -1;
	return (sp_int)strlen(sp_nk_set_out(value));
}

sp_int sp_NokoNode_attr_count(sp_NokoNode *self)
{
	sp_int n = 0;
	xmlAttrPtr a;
	if (self->node->type != XML_ELEMENT_NODE)
		return 0;
	for (a = self->node->properties; a; a = a->next)
		n++;
	return n;
}

const char *sp_NokoNode_attr_name(sp_NokoNode *self, sp_int i)
{
	xmlAttrPtr a = self->node->properties;
	while (a && i-- > 0)
		a = a->next;
	return a ? (const char *)a->name : "";
}

/* ---- writing ----------------------------------------------------------- */

void sp_NokoNode_set_name(sp_NokoNode *self, const char *name)
{
	xmlNodeSetName(self->node, (const xmlChar *)name);
}

void sp_NokoNode_set_attr(sp_NokoNode *self, const char *name, const char *value)
{
	xmlSetProp(self->node, (const xmlChar *)name, (const xmlChar *)value);
}

/* Node#remove_attribute: the gem's `attribute(name)&.unlink` -- unlinked,
   not freed, so a handle to the attribute stays valid (Loofah removes
   attributes by name while it holds them); listed with the document. */
void sp_NokoNode_remove_attr(sp_NokoNode *self, const char *name)
{
	xmlAttrPtr a = xmlHasProp(self->node, (const xmlChar *)name);
	if (!a)
		return;
	xmlUnlinkNode((xmlNodePtr)a);
	pthread_mutex_lock(&sp_nk_lock);
	sp_nk_list(self->owner, (xmlNodePtr)a);
	pthread_mutex_unlock(&sp_nk_lock);
}

/* Node#attribute_nodes: the i-th attribute, as a node of its own
   (XML::Attr). An xmlAttr shares xmlNode's leading fields, which is how
   libxml2 itself passes one where a node goes. */
sp_NokoNode *sp_NokoNode_attr_node(sp_NokoNode *self, sp_int i)
{
	xmlAttrPtr a = self->node->type == XML_ELEMENT_NODE ? self->node->properties : NULL;
	while (a && i-- > 0)
		a = a->next;
	return sp_nk_wrap(self->cls_id, (xmlNodePtr)a, self->owner);
}

/* Node#attribute(name): xmlHasProp, as the gem's is. */
sp_NokoNode *sp_NokoNode_attr_named(sp_NokoNode *self, const char *name)
{
	xmlAttrPtr a = self->node->type == XML_ELEMENT_NODE ? xmlHasProp(self->node, (const xmlChar *)name) : NULL;
	return sp_nk_wrap(self->cls_id, (xmlNodePtr)a, self->owner);
}

/* Attr#value=: the gem's set_value (xml_attr.c) -- the old children freed,
   the value's entities encoded and parsed back into a node list. */
void sp_NokoNode_set_attr_value(sp_NokoNode *self, const char *value)
{
	xmlAttrPtr attr = (xmlAttrPtr)self->node;
	xmlChar *enc;
	xmlNodePtr cur;
	if (attr->type != XML_ATTRIBUTE_NODE)
		return;
	if (attr->children)
		xmlFreeNodeList(attr->children);
	attr->children = attr->last = NULL;
	enc = xmlEncodeEntitiesReentrant(attr->doc, (const xmlChar *)value);
	if (xmlStrlen(enc) == 0)
		attr->children = xmlNewDocText(attr->doc, enc);
	else
		attr->children = xmlStringGetNodeList(attr->doc, enc);
	xmlFree(enc);
	for (cur = attr->children; cur; cur = cur->next) {
		cur->parent = (xmlNodePtr)attr;
		cur->doc = attr->doc;
		attr->last = cur;
	}
}

/* Node#encode_special_chars: xmlEncodeSpecialChars in the node's document. */
sp_int sp_NokoNode_encode_special_chars(sp_NokoNode *self, const char *s)
{
	return (sp_int)strlen(sp_nk_set_out(xmlEncodeSpecialChars(self->node->doc, (const xmlChar *)s)));
}

/* Node#content=: Nokogiri encodes the special characters and sets the
   result as the content (so "<" stays text). */
void sp_NokoNode_set_content(sp_NokoNode *self, const char *text)
{
	xmlChar *enc = xmlEncodeSpecialChars(self->node->doc, (const xmlChar *)text);
	xmlNodeSetContent(self->node, enc);
	xmlFree(enc);
}

/* Text#content=: a text or CDATA node's content, as given (libxml2 sets it
   raw on those node types). */
void sp_NokoNode_set_raw_content(sp_NokoNode *self, const char *text)
{
	xmlNodeSetContentLen(self->node, (const xmlChar *)text, (int)sp_str_byte_len(text));
}

/* Document#create_element(name): a new element in this document, listed
   until something puts it into the tree. */
sp_NokoNode *sp_NokoNode_create_element(sp_NokoNode *self, const char *name)
{
	xmlNodePtr n = xmlNewDocNode(self->owner->doc, NULL, (const xmlChar *)name, NULL);
	pthread_mutex_lock(&sp_nk_lock);
	sp_nk_list(self->owner, n);
	pthread_mutex_unlock(&sp_nk_lock);
	return sp_nk_wrap(self->cls_id, n, self->owner);
}

sp_NokoNode *sp_NokoNode_create_text(sp_NokoNode *self, const char *text)
{
	xmlNodePtr n = xmlNewDocText(self->owner->doc, (const xmlChar *)text);
	pthread_mutex_lock(&sp_nk_lock);
	sp_nk_list(self->owner, n);
	pthread_mutex_unlock(&sp_nk_lock);
	return sp_nk_wrap(self->cls_id, n, self->owner);
}

/* Document#create_cdata: xmlNewCDataBlock, listed like any new node. */
sp_NokoNode *sp_NokoNode_create_cdata(sp_NokoNode *self, const char *text)
{
	xmlNodePtr n = xmlNewCDataBlock(self->owner->doc, (const xmlChar *)text, (int)sp_str_byte_len(text));
	pthread_mutex_lock(&sp_nk_lock);
	sp_nk_list(self->owner, n);
	pthread_mutex_unlock(&sp_nk_lock);
	return sp_nk_wrap(self->cls_id, n, self->owner);
}

/* A document fragment node, as HTML4::DocumentFragment reparents a parse's
   nodes into. Parentless, so listed (freed with the document). Its nodes
   serialize as the gem's do: libxml2's HTML writer puts a newline after a
   block element only under a NAMED parent, and a fragment has no name. */
sp_NokoNode *sp_NokoNode_create_fragment(sp_NokoNode *self)
{
	xmlNodePtr n = xmlNewDocFragment(self->owner->doc);
	pthread_mutex_lock(&sp_nk_lock);
	sp_nk_list(self->owner, n);
	pthread_mutex_unlock(&sp_nk_lock);
	return sp_nk_wrap(self->cls_id, n, self->owner);
}

/* Unlink, listing the node with its document (freed with it). */
void sp_NokoNode_unlink(sp_NokoNode *self)
{
	xmlUnlinkNode(self->node);
	pthread_mutex_lock(&sp_nk_lock);
	sp_nk_list(self->owner, self->node);
	pthread_mutex_unlock(&sp_nk_lock);
}


/* Nokogiri's relink_namespace, run on every node it reparents: an element
   (or attribute) with no prefixed namespace takes the one its name's prefix
   -- or, unprefixed, the default namespace -- resolves to where it now is;
   a definition an ancestor already makes is dropped (kept with the owner,
   as the gem pins it to the document); and the walk continues into
   children and attributes while the node has a namespace. The gem's
   `namespace_inheritance` branch is off by default and not ported. */
static void sp_nk_relink(sp_nk_owner *o, xmlNodePtr n)
{
	xmlNodePtr child;
	xmlAttrPtr attr;
	if (n->type != XML_ATTRIBUTE_NODE && n->type != XML_ELEMENT_NODE)
		return;
	if (n->ns == NULL || n->ns->prefix == NULL) {
		xmlNsPtr ns;
		xmlChar *prefix = NULL;
		xmlChar *name = xmlSplitQName2(n->name, &prefix);
		if (n->type == XML_ATTRIBUTE_NODE &&
		    (prefix == NULL || strcmp((char *)prefix, "xmlns") == 0)) {
			xmlFree(name);
			xmlFree(prefix);
			return;
		}
		ns = xmlSearchNs(n->doc, n, prefix);
		if (ns != NULL) {
			xmlNodeSetName(n, name);
			xmlSetNs(n, ns);
		}
		xmlFree(name);
		xmlFree(prefix);
	}
	if (n->type != XML_ELEMENT_NODE || !n->parent)
		return;
	if (n->nsDef) {
		xmlNsPtr curr = n->nsDef, prev = NULL, next;
		while (curr) {
			xmlNsPtr ns = xmlSearchNsByHref(n->doc, n->parent, curr->href);
			next = curr->next;
			if (ns && ns != curr && xmlStrEqual(ns->prefix, curr->prefix)) {
				if (prev)
					prev->next = next;
				else
					n->nsDef = next;
				curr->next = o->removed_ns;
				o->removed_ns = curr;
			} else {
				prev = curr;
			}
			curr = next;
		}
	}
	if (n->ns) {
		xmlNsPtr ns = xmlSearchNs(n->doc, n, n->ns->prefix);
		if (ns && ns != n->ns && xmlStrEqual(ns->prefix, n->ns->prefix) &&
		    xmlStrEqual(ns->href, n->ns->href))
			xmlSetNs(n, ns);
	}
	if (n->ns == NULL)
		return;
	for (child = n->children; child; child = child->next)
		sp_nk_relink(o, child);
	for (attr = n->properties; attr; attr = attr->next)
		sp_nk_relink(o, (xmlNodePtr)attr);
}

/* The reparenting primitives Nokogiri's add_* are built from -- the gem's
   reparent_node_with. A node from another document, or a text node, is
   not moved but COPIED into this document: libxml2 merges an inserted
   text node into an adjacent one (freeing it), and a node carries its own
   document's string dictionary. The original is unlinked and listed with
   its own owner (so every handle to it stays valid), and, as in the gem,
   the handle the caller passed now holds the node that went in. */
enum { SP_NK_CHILD, SP_NK_PREV, SP_NK_NEXT, SP_NK_REPLACE };

static sp_NokoNode *sp_nk_reparent(sp_NokoNode *self, sp_RbVal arg, int how)
{
	sp_NokoNode *h = sp_nk_arg(arg);
	xmlNodePtr n = h->node, r;
	if (n->doc != self->owner->doc || n->type == XML_TEXT_NODE) {
		int default_ns = n->ns != NULL && n->ns->prefix == NULL;
		xmlNodePtr copy = xmlDocCopyNode(n, self->owner->doc, 1);
		if (default_ns && copy->ns != NULL && copy->ns->prefix != NULL) {
			/* xmlNewReconciledNs names a default namespace "default" */
			xmlFree((xmlChar *)copy->ns->prefix);
			copy->ns->prefix = NULL;
		}
		xmlUnlinkNode(n);
		pthread_mutex_lock(&sp_nk_lock);
		sp_nk_list(h->owner, n);
		pthread_mutex_unlock(&sp_nk_lock);
		n = copy;
	} else {
		xmlUnlinkNode(n);
	}
	if (how == SP_NK_REPLACE && n->type == XML_TEXT_NODE && self->node->next &&
	    self->node->next->type == XML_TEXT_NODE) {
		/* libxml2 merges the text that follows into the inserted text,
		   freeing it; a handle may hold it, so it is listed and a copy
		   takes its place (the gem's "totally lame" dance). */
		xmlNodePtr next_text = self->node->next;
		xmlNodePtr new_next = xmlDocCopyNode(next_text, self->owner->doc, 1);
		xmlUnlinkNode(next_text);
		pthread_mutex_lock(&sp_nk_lock);
		sp_nk_list(self->owner, next_text);
		pthread_mutex_unlock(&sp_nk_lock);
		xmlAddNextSibling(self->node, new_next);
	}
	if (how == SP_NK_REPLACE) {
		/* the gem's xmlReplaceNodeWrapper: then merge adjacent text */
		r = xmlReplaceNode(self->node, n);
		if (r == self->node)
			r = n;
		if (r && r->type == XML_TEXT_NODE) {
			if (r->prev && r->prev->type == XML_TEXT_NODE)
				r = xmlTextMerge(r->prev, r);
			if (r->next && r->next->type == XML_TEXT_NODE)
				r = xmlTextMerge(r, r->next);
		}
		pthread_mutex_lock(&sp_nk_lock);
		sp_nk_list(self->owner, self->node);
		pthread_mutex_unlock(&sp_nk_lock);
	} else if (how == SP_NK_CHILD)
		r = xmlAddChild(self->node, n);
	else if (how == SP_NK_PREV)
		r = xmlAddPrevSibling(self->node, n);
	else
		r = xmlAddNextSibling(self->node, n);
	if (!r)
		return sp_NokoNode_new(self->cls_id);
	pthread_mutex_lock(&sp_nk_lock);
	sp_nk_relink(self->owner, r);
	if (h->owner != self->owner) {
		self->owner->refs++;
		sp_nk_release_locked(h->owner);
		h->owner = self->owner;
	}
	h->node = r;
	pthread_mutex_unlock(&sp_nk_lock);
	return sp_nk_wrap(self->cls_id, r, self->owner);
}

sp_NokoNode *sp_NokoNode_add_previous_sibling(sp_NokoNode *self, sp_RbVal arg)
{
	return sp_nk_reparent(self, arg, SP_NK_PREV);
}

sp_NokoNode *sp_NokoNode_add_next_sibling(sp_NokoNode *self, sp_RbVal arg)
{
	return sp_nk_reparent(self, arg, SP_NK_NEXT);
}

sp_NokoNode *sp_NokoNode_add_child(sp_NokoNode *self, sp_RbVal arg)
{
	return sp_nk_reparent(self, arg, SP_NK_CHILD);
}

/* Node#replace with one node: it takes this node's place. */
sp_NokoNode *sp_NokoNode_replace(sp_NokoNode *self, sp_RbVal arg)
{
	return sp_nk_reparent(self, arg, SP_NK_REPLACE);
}

/* Node#dup(level): a copy in the same document (level 1 with its
   children, 0 without), listed until something puts it into the tree. */
sp_NokoNode *sp_NokoNode_dup(sp_NokoNode *self, sp_int level)
{
	xmlNodePtr n = xmlDocCopyNode(self->node, self->owner->doc, (int)level);
	if (!n)
		return sp_NokoNode_new(self->cls_id);
	pthread_mutex_lock(&sp_nk_lock);
	sp_nk_list(self->owner, n);
	pthread_mutex_unlock(&sp_nk_lock);
	return sp_nk_wrap(self->cls_id, n, self->owner);
}

/* ---- parsing in a node's context --------------------------------------- */

/* The last in_context parse's top-level nodes, per thread, read out one by
   one. */
static SP_TLS xmlNodePtr *sp_nk_ic = NULL;
static SP_TLS size_t sp_nk_ic_n = 0;

/* Node#in_context(string, options): the gem's -- xmlParseInNodeContext,
   its errors added to the document's, the child pointers put back when
   the parse failed, and each top-level node listed with the document
   (the gem pins them). Answers the number of nodes. */
sp_int sp_NokoNode_in_context(sp_NokoNode *self, const char *str, sp_int options)
{
	xmlNodePtr node = self->node, list = NULL, tmp, it;
	xmlNodePtr node_children = node->children, doc_children = node->doc->children;
	int doc_is_empty = node->doc->children == NULL;
	xmlParserErrors error;
	sp_nk_errs *e;
	size_t i;

	free(sp_nk_ic);
	sp_nk_ic = NULL;
	sp_nk_ic_n = 0;
	sp_nk_begin_parse();
	error = xmlParseInNodeContext(node, str, (int)sp_str_byte_len(str), (int)options, &list);
	xmlSetStructuredErrorFunc(NULL, NULL);
	if (error != XML_ERR_OK) {
		node->doc->children = doc_children;
		node->children = node_children;
	}
	for (it = node->doc->children; it; it = it->next)
		it->parent = (xmlNodePtr)node->doc;
	if (error != XML_ERR_OK && doc_is_empty && node->doc->children != NULL) {
		for (it = node; it->parent; it = it->parent)
			;
		if (it->type == XML_DOCUMENT_FRAG_NODE)
			node->doc->children = NULL;
	}

	pthread_mutex_lock(&sp_nk_lock);
	e = &self->owner->errs;
	for (i = 0; i < sp_nk_parse_errs.n; i++) {
		if (e->n == e->cap) {
			e->cap = e->cap ? e->cap * 2 : 8;
			e->v = (sp_nk_err *)realloc(e->v, e->cap * sizeof(sp_nk_err));
		}
		e->v[e->n++] = sp_nk_parse_errs.v[i];
	}
	free(sp_nk_parse_errs.v);
	sp_nk_parse_errs.v = NULL;
	sp_nk_parse_errs.n = sp_nk_parse_errs.cap = 0;
	while (list) {
		tmp = list->next;
		list->next = NULL;
		list->prev = NULL;
		sp_nk_list(self->owner, list);
		sp_nk_ic = (xmlNodePtr *)realloc(sp_nk_ic, (sp_nk_ic_n + 1) * sizeof(xmlNodePtr));
		sp_nk_ic[sp_nk_ic_n++] = list;
		list = tmp;
	}
	pthread_mutex_unlock(&sp_nk_lock);
	return (sp_int)sp_nk_ic_n;
}

sp_NokoNode *sp_NokoNode_in_context_result(sp_NokoNode *self, sp_int i)
{
	xmlNodePtr n = (i >= 0 && (size_t)i < sp_nk_ic_n) ? sp_nk_ic[i] : NULL;
	return sp_nk_wrap(self->cls_id, n, self->owner);
}

/* ---- XPath ------------------------------------------------------------- */

/* The last query's result nodes, per thread, read out one by one. Only
   the pointers are kept: the XPath object is freed before the query
   returns, because freeing it later walks its node set, and by then the
   GC may have freed the document those nodes were in. */
static SP_TLS xmlNodePtr *sp_nk_xp = NULL;
static SP_TLS size_t sp_nk_xp_n = 0;

/* Nokogiri installs its own error handler, so libxml2 prints nothing for a
   bad expression (the gem raises XPath::SyntaxError instead, with
   libxml2's message). The same here: the context's structured handler
   keeps the message, and the NULL result is what the Ruby side raises on. */
static SP_TLS char *sp_nk_xp_err = NULL;

static void sp_nk_xpath_error(void *ctx, const xmlError *err)
{
	size_t len;
	(void)ctx;
	free(sp_nk_xp_err);
	sp_nk_xp_err = strdup(err->message ? err->message : "");
	len = strlen(sp_nk_xp_err);
	while (len > 0 && sp_nk_xp_err[len - 1] == '\n')
		sp_nk_xp_err[--len] = '\0';
}

const char *sp_noko_xpath_error(void)
{
	return sp_nk_xp_err ? sp_nk_xp_err : "";
}

/* Registers "prefix\thref\n" lines, as the gem registers the namespace
   hash an xpath call is given (by default, the root's namespaces). */
static void sp_nk_register_ns(xmlXPathContextPtr ctx, const char *bindings)
{
	char *copy = strdup(bindings), *line = copy, *nl, *tab;
	while (*line) {
		nl = strchr(line, '\n');
		if (nl)
			*nl = '\0';
		tab = strchr(line, '\t');
		if (tab) {
			*tab = '\0';
			xmlXPathRegisterNs(ctx, (const xmlChar *)line, (const xmlChar *)(tab + 1));
		}
		if (!nl)
			break;
		line = nl + 1;
	}
	free(copy);
}

/* Evaluates `expr` with `self` as the context node and `bindings`
   registered. Answers the number of nodes, or -1 when libxml2 rejects the
   expression (Nokogiri raises Nokogiri::XML::XPath::SyntaxError), or -2
   when it is not a node set. */
sp_int sp_NokoNode_xpath(sp_NokoNode *self, const char *expr, const char *bindings)
{
	xmlXPathContextPtr ctx;
	xmlXPathObjectPtr res;
	int i;
	free(sp_nk_xp);
	sp_nk_xp = NULL;
	sp_nk_xp_n = 0;
	free(sp_nk_xp_err);
	sp_nk_xp_err = NULL;
	ctx = xmlXPathNewContext(self->owner->doc);
	ctx->node = self->node;
	ctx->error = sp_nk_xpath_error;
	/* The gem's XPathContext binds its handler namespace in every query,
	   so a `nokogiri:` function no handler defines (what `:even` or
	   `:checked` become) fails as "Unregistered function". */
	xmlXPathRegisterNs(ctx, (const xmlChar *)"nokogiri",
	                   (const xmlChar *)"http://www.nokogiri.org/default_ns/ruby/extensions_functions");
	sp_nk_register_ns(ctx, bindings);
	res = xmlXPathEvalExpression((const xmlChar *)expr, ctx);
	xmlXPathFreeContext(ctx);
	if (!res)
		return -1;
	if (res->type != XPATH_NODESET) {
		xmlXPathFreeObject(res);
		return -2;
	}
	if (res->nodesetval && res->nodesetval->nodeNr > 0) {
		sp_nk_xp = (xmlNodePtr *)malloc((size_t)res->nodesetval->nodeNr * sizeof(xmlNodePtr));
		for (i = 0; i < res->nodesetval->nodeNr; i++) {
			xmlNodePtr n = res->nodesetval->nodeTab[i];
			/* a namespace node is the set's own copy, freed with it */
			if (n->type != XML_NAMESPACE_DECL)
				sp_nk_xp[sp_nk_xp_n++] = n;
		}
	}
	xmlXPathFreeObject(res);
	return (sp_int)sp_nk_xp_n;
}

sp_NokoNode *sp_NokoNode_xpath_result(sp_NokoNode *self, sp_int i)
{
	xmlNodePtr n = (i >= 0 && (size_t)i < sp_nk_xp_n) ? sp_nk_xp[i] : NULL;
	return sp_nk_wrap(self->cls_id, n, self->owner);
}

/* ---- serialization ----------------------------------------------------- */

/* Node#to_html / #to_xml / #write_to: xmlSaveTree through a save context,
   with Nokogiri's SaveOptions bits and the document's encoding. */
sp_int sp_NokoNode_serialize(sp_NokoNode *self, sp_int options)
{
	xmlBufferPtr buf = xmlBufferCreate();
	const char *enc = self->owner->doc->encoding ? (const char *)self->owner->doc->encoding : NULL;
	xmlSaveCtxtPtr ctx = xmlSaveToBuffer(buf, enc, (int)options);
	xmlSaveTree(ctx, self->node);
	xmlSaveClose(ctx);
	free(sp_nk_out);
	sp_nk_out = strdup((const char *)xmlBufferContent(buf));
	xmlBufferFree(buf);
	return (sp_int)strlen(sp_nk_out);
}

const char *sp_NokoNode_encoding(sp_NokoNode *self)
{
	return self->owner->doc->encoding ? (const char *)self->owner->doc->encoding : "";
}

/* XML::Document#version. */
const char *sp_NokoNode_version(sp_NokoNode *self)
{
	return self->owner->doc->version ? (const char *)self->owner->doc->version : "";
}

/* ---- namespaces -------------------------------------------------------- */

/* Namespaces cross as "prefix\thref" lines (an empty prefix is the default
   namespace), through the out buffer. */
static void sp_nk_ns_line(xmlBufferPtr buf, xmlNsPtr ns)
{
	if (ns->prefix)
		xmlBufferCat(buf, ns->prefix);
	xmlBufferCat(buf, (const xmlChar *)"\t");
	if (ns->href)
		xmlBufferCat(buf, ns->href);
	xmlBufferCat(buf, (const xmlChar *)"\n");
}

static sp_int sp_nk_out_buffer(xmlBufferPtr buf)
{
	free(sp_nk_out);
	sp_nk_out = strdup((const char *)xmlBufferContent(buf));
	xmlBufferFree(buf);
	return (sp_int)strlen(sp_nk_out);
}

static int sp_nk_has_ns(xmlNodePtr n)
{
	return n->type == XML_ELEMENT_NODE || n->type == XML_ATTRIBUTE_NODE;
}

/* Node#namespace: the node's own namespace, or nothing. */
sp_int sp_NokoNode_namespace(sp_NokoNode *self)
{
	xmlBufferPtr buf = xmlBufferCreate();
	if (sp_nk_has_ns(self->node) && self->node->ns)
		sp_nk_ns_line(buf, self->node->ns);
	return sp_nk_out_buffer(buf);
}

/* Node#namespace_scopes (what #namespaces is built from): xmlGetNsList,
   innermost definition first, a shadowed prefix given once. */
sp_int sp_NokoNode_namespace_scopes(sp_NokoNode *self)
{
	xmlBufferPtr buf = xmlBufferCreate();
	xmlNsPtr *list;
	int i;
	if (self->node->type == XML_ELEMENT_NODE) {
		list = xmlGetNsList(self->owner->doc, self->node);
		if (list) {
			for (i = 0; list[i]; i++)
				sp_nk_ns_line(buf, list[i]);
			xmlFree(list);
		}
	}
	return sp_nk_out_buffer(buf);
}

/* Node#namespace_definitions: the ones declared on this element. */
sp_int sp_NokoNode_namespace_definitions(sp_NokoNode *self)
{
	xmlBufferPtr buf = xmlBufferCreate();
	xmlNsPtr ns;
	if (self->node->type == XML_ELEMENT_NODE)
		for (ns = self->node->nsDef; ns; ns = ns->next)
			sp_nk_ns_line(buf, ns);
	return sp_nk_out_buffer(buf);
}

/* Document#remove_namespaces!: the gem's recursion -- every node loses its
   namespace, every element its definitions (kept with the owner, freed
   with the document), every attribute its namespace. */
static void sp_nk_remove_ns(sp_nk_owner *o, xmlNodePtr node)
{
	xmlNodePtr child;
	xmlAttrPtr a;
	xmlNsPtr tail;
	if (sp_nk_has_ns(node))
		xmlSetNs(node, NULL);
	for (child = node->children; child; child = child->next)
		sp_nk_remove_ns(o, child);
	if (node->type == XML_ELEMENT_NODE && node->nsDef) {
		for (tail = node->nsDef; tail->next; tail = tail->next)
			;
		tail->next = o->removed_ns;
		o->removed_ns = node->nsDef;
		node->nsDef = NULL;
	}
	if (node->type == XML_ELEMENT_NODE)
		for (a = node->properties; a; a = a->next)
			a->ns = NULL;
}

void sp_NokoNode_remove_namespaces(sp_NokoNode *self)
{
	pthread_mutex_lock(&sp_nk_lock);
	sp_nk_remove_ns(self->owner, self->node);
	pthread_mutex_unlock(&sp_nk_lock);
}

/* ---- node facts -------------------------------------------------------- */

/* Node#path: xmlGetNodePath, as the gem answers it. */
sp_int sp_NokoNode_path(sp_NokoNode *self)
{
	return (sp_int)strlen(sp_nk_set_out(xmlGetNodePath(self->node)));
}

/* Node#line: xmlGetLineNo (BIG_LINES is in both default parse options). */
sp_int sp_NokoNode_line(sp_NokoNode *self)
{
	return (sp_int)xmlGetLineNo(self->node);
}

/* Node#blank?: xmlIsBlankNode -- a text node of whitespace only. */
sp_bool sp_NokoNode_blank_p(sp_NokoNode *self)
{
	return xmlIsBlankNode(self->node) == 1;
}

/* ---- HTML5 (gumbo) ----------------------------------------------------- */

/* Ported from Nokogiri's ext/nokogiri/gumbo.c (1.19.4):
 *
 *   Copyright 2013-2021 Sam Ruby, Stephen Checkoway
 *
 *   Licensed under the Apache License, Version 2.0 (the "License"); you may
 *   not use this file except in compliance with the License. You may obtain
 *   a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
 *   (and gumbo/LICENSE). Unless required by applicable law or agreed to in
 *   writing, software distributed under the License is distributed on an
 *   "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 *   express or implied.
 *
 * Nokogiri's gumbo.c, off the Ruby C API: gumbo parses, and its tree is
   rebuilt as a libxml2 tree -- elements in the SVG and MathML namespaces
   under the prefixes Nokogiri gives them -- so everything else (XPath,
   editing) is the libxml2 code the rest of the package already uses. */

static xmlNsPtr sp_nk_ns_for(xmlDocPtr doc, xmlNodePtr root, const char *href, const char *prefix)
{
	xmlNsPtr ns = xmlSearchNs(doc, root, (const xmlChar *)prefix);
	if (ns)
		return ns;
	return xmlNewNs(root, (const xmlChar *)href, (const xmlChar *)prefix);
}

static void sp_nk_set_line(xmlNodePtr node, size_t line)
{
	if (line < 65535)
		node->line = (unsigned short)line;
}

/* gumbo.c's build_tree, verbatim in effect. */
static void sp_nk_build_tree(xmlDocPtr doc, xmlNodePtr xml_output_node, const GumboNode *gumbo_node)
{
	xmlNodePtr xml_root = NULL;
	xmlNodePtr xml_node = xml_output_node;
	size_t child_index = 0;

	while (1) {
		const GumboVector *children = gumbo_node->type == GUMBO_NODE_DOCUMENT ?
		    &gumbo_node->v.document.children : &gumbo_node->v.element.children;
		const GumboNode *gumbo_child;
		xmlNodePtr xml_child;
		if (child_index >= children->length) {
			if (xml_node == xml_output_node)
				return;
			child_index = gumbo_node->index_within_parent + 1;
			gumbo_node = gumbo_node->parent;
			xml_node = xml_node->parent;
			if (xml_node == xml_output_node)
				xml_root = NULL;
			continue;
		}
		gumbo_child = children->data[child_index++];
		switch (gumbo_child->type) {
		case GUMBO_NODE_DOCUMENT:
			abort();
		case GUMBO_NODE_TEXT:
		case GUMBO_NODE_WHITESPACE:
			xml_child = xmlNewDocText(doc, (const xmlChar *)gumbo_child->v.text.text);
			sp_nk_set_line(xml_child, gumbo_child->v.text.start_pos.line);
			xmlAddChild(xml_node, xml_child);
			break;
		case GUMBO_NODE_CDATA:
			xml_child = xmlNewCDataBlock(doc, (const xmlChar *)gumbo_child->v.text.text,
			                             (int)strlen(gumbo_child->v.text.text));
			sp_nk_set_line(xml_child, gumbo_child->v.text.start_pos.line);
			xmlAddChild(xml_node, xml_child);
			break;
		case GUMBO_NODE_COMMENT:
			xml_child = xmlNewDocComment(doc, (const xmlChar *)gumbo_child->v.text.text);
			sp_nk_set_line(xml_child, gumbo_child->v.text.start_pos.line);
			xmlAddChild(xml_node, xml_child);
			break;
		case GUMBO_NODE_TEMPLATE:
		case GUMBO_NODE_ELEMENT: {
			xmlNsPtr ns = NULL;
			const GumboVector *attrs;
			size_t i;
			xml_child = xmlNewDocNode(doc, NULL, (const xmlChar *)gumbo_child->v.element.name, NULL);
			sp_nk_set_line(xml_child, gumbo_child->v.element.start_pos.line);
			if (xml_root == NULL)
				xml_root = xml_child;
			switch (gumbo_child->v.element.tag_namespace) {
			case GUMBO_NAMESPACE_HTML:
				break;
			case GUMBO_NAMESPACE_SVG:
				ns = sp_nk_ns_for(doc, xml_root, "http://www.w3.org/2000/svg", "svg");
				break;
			case GUMBO_NAMESPACE_MATHML:
				ns = sp_nk_ns_for(doc, xml_root, "http://www.w3.org/1998/Math/MathML", "math");
				break;
			}
			if (ns != NULL)
				xmlSetNs(xml_child, ns);
			xmlAddChild(xml_node, xml_child);
			attrs = &gumbo_child->v.element.attributes;
			for (i = 0; i < attrs->length; i++) {
				const GumboAttribute *attr = attrs->data[i];
				switch (attr->attr_namespace) {
				case GUMBO_ATTR_NAMESPACE_XLINK:
					ns = sp_nk_ns_for(doc, xml_root, "http://www.w3.org/1999/xlink", "xlink");
					break;
				case GUMBO_ATTR_NAMESPACE_XML:
					ns = sp_nk_ns_for(doc, xml_root, "http://www.w3.org/XML/1998/namespace", "xml");
					break;
				case GUMBO_ATTR_NAMESPACE_XMLNS:
					ns = sp_nk_ns_for(doc, xml_root, "http://www.w3.org/2000/xmlns/", "xmlns");
					break;
				default:
					ns = NULL;
				}
				xmlNewNsProp(xml_child, ns, (const xmlChar *)attr->name, (const xmlChar *)attr->value);
			}
			child_index = 0;
			gumbo_node = gumbo_child;
			xml_node = xml_child;
		}
		}
	}
}

/* gumbo.c's add_errors: each error as a SyntaxError at level 2 (ERROR),
   its message gumbo's caret diagnostic. Collected where a parse's errors
   go (sp_nk_parse_errs). */
static void sp_nk_gumbo_errors(const GumboOutput *output, const char *input, size_t len)
{
	size_t i;
	sp_nk_errs *e = &sp_nk_parse_errs;
	for (i = 0; i < output->errors.length; i++) {
		GumboError *err = output->errors.data[i];
		GumboSourcePosition pos = gumbo_error_position(err);
		char *msg = NULL;
		size_t size = gumbo_caret_diagnostic_to_string(err, input, len, &msg);
		if (e->n == e->cap) {
			e->cap = e->cap ? e->cap * 2 : 8;
			e->v = (sp_nk_err *)realloc(e->v, e->cap * sizeof(sp_nk_err));
		}
		e->v[e->n].level = 2;
		e->v[e->n].line = (int)pos.line;
		e->v[e->n].column = (int)pos.column;
		e->v[e->n].message = (char *)malloc(size + 1);
		memcpy(e->v[e->n].message, msg, size);
		e->v[e->n].message[size] = '\0';
		free(msg);
		e->n++;
	}
}

/* gumbo's refusal of a parse (too many attributes, too deep), for the
   ArgumentError the gem raises; "" when the parse went through. */
static SP_TLS const char *sp_nk_gumbo_status = "";

const char *sp_noko_gumbo_status(void)
{
	return sp_nk_gumbo_status;
}

static GumboOptions sp_nk_gumbo_options(sp_int max_attributes, sp_int max_errors, sp_int max_depth, sp_bool noscript_text)
{
	GumboOptions options = kGumboDefaultOptions;
	options.max_attributes = (int)max_attributes;
	options.max_errors = (int)max_errors;
	options.max_tree_depth = max_depth < 0 ? UINT_MAX : (unsigned int)max_depth;
	options.parse_noscript_content_as_text = noscript_text;
	return options;
}

static GumboOutput *sp_nk_gumbo_parse(const GumboOptions *options, const char *input)
{
	GumboOutput *output = gumbo_parse_with_options(options, input, sp_str_byte_len(input));
	sp_nk_gumbo_status = "";
	if (output->status != GUMBO_STATUS_OK) {
		sp_nk_gumbo_status = gumbo_status_to_string(output->status);
		gumbo_destroy_output(output);
		return NULL;
	}
	return output;
}

/* Nokogiri::HTML5::Document.parse: the document gumbo's doctype names
   (or none), built, its encoding UTF-8 as the gem sets it. An empty handle
   when gumbo refuses (sp_noko_gumbo_status says why). */
sp_NokoNode *sp_NokoNode_parse_html5(sp_NokoNode *self, const char *html, sp_int max_attributes,
                                    sp_int max_errors, sp_int max_depth, sp_bool noscript_text)
{
	GumboOptions options = sp_nk_gumbo_options(max_attributes, max_errors, max_depth, noscript_text);
	GumboOutput *output;
	htmlDocPtr doc;
	sp_NokoNode *h;
	sp_nk_begin_parse();
	xmlSetStructuredErrorFunc(NULL, NULL);
	output = sp_nk_gumbo_parse(&options, html);
	if (!output)
		return sp_NokoNode_new(self->cls_id);
	doc = htmlNewDocNoDtD(NULL, NULL);
	if (output->document->v.document.has_doctype) {
		const char *pub = output->document->v.document.public_identifier;
		const char *sys = output->document->v.document.system_identifier;
		xmlCreateIntSubset(doc, (const xmlChar *)output->document->v.document.name,
		                   pub[0] ? (const xmlChar *)pub : NULL, sys[0] ? (const xmlChar *)sys : NULL);
	}
	sp_nk_build_tree(doc, (xmlNodePtr)doc, output->document);
	doc->encoding = xmlStrdup((const xmlChar *)"UTF-8");
	sp_nk_gumbo_errors(output, html, sp_str_byte_len(html));
	h = sp_nk_own(self->cls_id, doc);
	h->owner->html5 = 1;
	h->owner->quirks_mode = (int)output->document->v.document.doc_type_quirks_mode;
	gumbo_destroy_output(output);
	return h;
}

/* HTML5::Document.new, which HTML5.fragment parses into: htmlNewDoc, as
   the gem's HTML4::Document.new makes one (with its default DTD). */
sp_NokoNode *sp_NokoNode_new_html5_document(sp_NokoNode *self)
{
	sp_NokoNode *h;
	htmlDocPtr doc = htmlNewDoc(NULL, NULL);
	doc->encoding = xmlStrdup((const xmlChar *)"UTF-8");
	sp_nk_begin_parse();
	xmlSetStructuredErrorFunc(NULL, NULL);
	h = sp_nk_own(self->cls_id, doc);
	h->owner->html5 = 1;
	return h;
}

/* HTML4::Document.new / HTML5::Document.new with no arguments: htmlNewDoc
   with its default DTD and no encoding, as the gem's new answers. */
sp_NokoNode *sp_NokoNode_new_html_document(sp_NokoNode *self, sp_bool html5)
{
	sp_NokoNode *h;
	htmlDocPtr doc = htmlNewDoc(NULL, NULL);
	sp_nk_begin_parse();
	xmlSetStructuredErrorFunc(NULL, NULL);
	h = sp_nk_own(self->cls_id, doc);
	h->owner->html5 = html5 ? 1 : 0;
	return h;
}

/* Document#encoding=: the gem's -- the name replaces the document's. */
void sp_NokoNode_set_encoding(sp_NokoNode *self, const char *encoding)
{
	xmlDocPtr doc = self->owner->doc;
	if (doc->encoding)
		xmlFree((xmlChar *)doc->encoding);
	doc->encoding = xmlStrdup((const xmlChar *)encoding);
}

sp_bool sp_NokoNode_html5_p(sp_NokoNode *self)
{
	return self->owner && self->owner->html5;
}

sp_int sp_NokoNode_quirks_mode(sp_NokoNode *self)
{
	return self->owner->quirks_mode;
}

/* gumbo.c's fragment parse into `self`, a fragment node. The context --
   its tag, namespace, a form ancestor, an annotation-xml encoding -- the
   Ruby side works out; the quirks mode comes from the document when the
   context is a node of a parsed HTML5 document, as in the gem. The
   fragment's errors are left in sp_nk_parse_errs for the Ruby side.
   Answers 0, or -1 when gumbo refuses. */
sp_int sp_NokoNode_html5_fragment(sp_NokoNode *self, const char *tags, const char *ctx_tag, sp_int ctx_ns,
                                  sp_bool form, const char *encoding, sp_bool ctx_is_node,
                                  sp_int max_attributes, sp_int max_errors, sp_int max_depth,
                                  sp_bool noscript_text)
{
	GumboOptions options = sp_nk_gumbo_options(max_attributes, max_errors, max_depth, noscript_text);
	GumboOutput *output;
	GumboQuirksModeEnum quirks;
	xmlDocPtr doc = self->owner->doc;
	xmlDtdPtr dtd = xmlGetIntSubset(doc);

	if (!ctx_is_node || self->owner->quirks_mode < 0)
		quirks = GUMBO_DOCTYPE_NO_QUIRKS;
	else if (dtd == NULL)
		quirks = GUMBO_DOCTYPE_QUIRKS;
	else
		quirks = gumbo_compute_quirks_mode((const char *)dtd->name, (const char *)dtd->ExternalID,
		                                   (const char *)dtd->SystemID);
	options.fragment_context = ctx_tag;
	options.fragment_namespace = (GumboNamespaceEnum)ctx_ns;
	options.fragment_encoding = *encoding ? encoding : NULL;
	options.quirks_mode = quirks;
	options.fragment_context_has_form_ancestor = form;
	if (options.max_tree_depth < UINT_MAX)
		options.max_tree_depth++;

	sp_nk_begin_parse();
	xmlSetStructuredErrorFunc(NULL, NULL);
	output = sp_nk_gumbo_parse(&options, tags);
	if (!output)
		return -1;
	sp_nk_build_tree(doc, self->node, output->root);
	sp_nk_gumbo_errors(output, tags, sp_str_byte_len(tags));
	gumbo_destroy_output(output);
	return 0;
}

/* The last parse's errors, when no document holds them (a fragment's). */
sp_int sp_noko_parse_error_count(void)
{
	return (sp_int)sp_nk_parse_errs.n;
}

/* ---- HTML5 serialization (xml_node.c's html_standard_serialize) --------- */

/* Ported from Nokogiri's ext/nokogiri/xml_node.c (1.19.4, MIT). */

static void sp_nk_out_tagname(xmlBufferPtr out, xmlNodePtr elem)
{
	const char *name = (const char *)elem->name;
	xmlNsPtr ns = elem->ns;
	if (ns && ns->href && ns->prefix
	    && strcmp((const char *)ns->href, "http://www.w3.org/1999/xhtml")
	    && strcmp((const char *)ns->href, "http://www.w3.org/1998/Math/MathML")
	    && strcmp((const char *)ns->href, "http://www.w3.org/2000/svg")) {
		const char *colon;
		xmlBufferCat(out, ns->prefix);
		xmlBufferCCat(out, ":");
		colon = strchr(name, ':');
		if (colon)
			name = colon + 1;
	}
	xmlBufferCCat(out, name);
}

static void sp_nk_out_attr_name(xmlBufferPtr out, xmlAttrPtr attr)
{
	xmlNsPtr ns = attr->ns;
	const char *name = (const char *)attr->name;
	if (ns && ns->href) {
		const char *uri = (const char *)ns->href;
		const char *localname = strchr(name, ':');
		localname = localname ? localname + 1 : name;
		if (!strcmp(uri, "http://www.w3.org/XML/1998/namespace")) {
			xmlBufferCCat(out, "xml:");
			name = localname;
		} else if (!strcmp(uri, "http://www.w3.org/2000/xmlns/")) {
			if (strcmp(localname, "xmlns"))
				xmlBufferCCat(out, "xmlns:");
			name = localname;
		} else if (!strcmp(uri, "http://www.w3.org/1999/xlink")) {
			xmlBufferCCat(out, "xlink:");
			name = localname;
		} else if (ns->prefix) {
			xmlBufferCat(out, ns->prefix);
			xmlBufferCCat(out, ":");
			name = localname;
		}
	}
	xmlBufferCCat(out, name);
}

static void sp_nk_out_escaped(xmlBufferPtr out, const xmlChar *start, int attr)
{
	const xmlChar *next = start;
	int ch;
	while ((ch = *next) != 0) {
		const char *replacement = NULL;
		size_t replaced = 1;
		if (ch == '&')
			replacement = "&amp;";
		else if (ch == 0xC2 && next[1] == 0xA0) {
			replacement = "&nbsp;";
			replaced = 2;
		} else if (attr && ch == '"')
			replacement = "&quot;";
		else if (!attr && ch == '<')
			replacement = "&lt;";
		else if (!attr && ch == '>')
			replacement = "&gt;";
		else {
			++next;
			continue;
		}
		if (next > start)
			xmlBufferAdd(out, start, (int)(next - start));
		xmlBufferCCat(out, replacement);
		next += replaced;
		start = next;
	}
	if (next > start)
		xmlBufferAdd(out, start, (int)(next - start));
}

static int sp_nk_prepend_newline(xmlNodePtr node)
{
	const char *name = (const char *)node->name;
	xmlNodePtr child = node->children;
	if (!name || !child || (strcmp(name, "pre") && strcmp(name, "textarea") && strcmp(name, "listing")))
		return 0;
	return child->type == XML_TEXT_NODE && child->content && child->content[0] == '\n';
}

static int sp_nk_is_one_of(xmlNodePtr node, const char *const *names, size_t n)
{
	const char *name = (const char *)node->name;
	size_t i;
	if (name == NULL || node->ns != NULL)
		return 0;
	for (i = 0; i < n; i++)
		if (!strcmp(name, names[i]))
			return 1;
	return 0;
}

static void sp_nk_out_node(xmlBufferPtr out, xmlNodePtr node, int preserve_newline)
{
	static const char *const VOID_ELEMENTS[] = {
		"area", "base", "basefont", "bgsound", "br", "col", "embed", "frame", "hr",
		"img", "input", "keygen", "link", "meta", "param", "source", "track", "wbr",
	};
	static const char *const UNESCAPED_TEXT_ELEMENTS[] = {
		"style", "script", "xmp", "iframe", "noembed", "noframes", "plaintext", "noscript",
	};
	xmlNodePtr child;
	switch (node->type) {
	case XML_ELEMENT_NODE: {
		xmlAttrPtr attr;
		xmlBufferCCat(out, "<");
		sp_nk_out_tagname(out, node);
		for (attr = node->properties; attr; attr = attr->next) {
			xmlBufferCCat(out, " ");
			sp_nk_out_node(out, (xmlNodePtr)attr, preserve_newline);
		}
		xmlBufferCCat(out, ">");
		if (!sp_nk_is_one_of(node, VOID_ELEMENTS, sizeof VOID_ELEMENTS / sizeof VOID_ELEMENTS[0])) {
			if (preserve_newline && sp_nk_prepend_newline(node))
				xmlBufferCCat(out, "\n");
			for (child = node->children; child; child = child->next)
				sp_nk_out_node(out, child, preserve_newline);
			xmlBufferCCat(out, "</");
			sp_nk_out_tagname(out, node);
			xmlBufferCCat(out, ">");
		}
		break;
	}
	case XML_ATTRIBUTE_NODE: {
		xmlAttrPtr attr = (xmlAttrPtr)node;
		sp_nk_out_attr_name(out, attr);
		if (attr->children) {
			xmlChar *value = xmlNodeListGetString(attr->doc, attr->children, 1);
			xmlBufferCCat(out, "=\"");
			sp_nk_out_escaped(out, value, 1);
			xmlFree(value);
			xmlBufferCCat(out, "\"");
		} else {
			xmlBufferCCat(out, "=\"\"");
		}
		break;
	}
	case XML_TEXT_NODE:
		if (node->parent && sp_nk_is_one_of(node->parent, UNESCAPED_TEXT_ELEMENTS,
		                                    sizeof UNESCAPED_TEXT_ELEMENTS / sizeof UNESCAPED_TEXT_ELEMENTS[0]))
			xmlBufferCat(out, node->content);
		else
			sp_nk_out_escaped(out, node->content, 0);
		break;
	case XML_CDATA_SECTION_NODE:
		xmlBufferCCat(out, "<![CDATA[");
		xmlBufferCat(out, node->content);
		xmlBufferCCat(out, "]]>");
		break;
	case XML_COMMENT_NODE:
		xmlBufferCCat(out, "<!--");
		xmlBufferCat(out, node->content);
		xmlBufferCCat(out, "-->");
		break;
	case XML_PI_NODE:
		xmlBufferCCat(out, "<?");
		xmlBufferCat(out, node->content);
		xmlBufferCCat(out, ">");
		break;
	case XML_DOCUMENT_TYPE_NODE:
	case XML_DTD_NODE:
		xmlBufferCCat(out, "<!DOCTYPE ");
		xmlBufferCat(out, node->name);
		xmlBufferCCat(out, ">");
		break;
	case XML_DOCUMENT_NODE:
	case XML_DOCUMENT_FRAG_NODE:
	case XML_HTML_DOCUMENT_NODE:
		for (child = node->children; child; child = child->next)
			sp_nk_out_node(out, child, preserve_newline);
		break;
	default:
		break;
	}
}

/* Node#to_html in an HTML5 document: the HTML standard's serialization. */
sp_int sp_NokoNode_html5_serialize(sp_NokoNode *self, sp_bool preserve_newline)
{
	xmlBufferPtr buf = xmlBufferCreate();
	sp_nk_out_node(buf, self->node, preserve_newline);
	return sp_nk_out_buffer(buf);
}

sp_int sp_noko_parse_error_level(sp_int i)
{
	return sp_nk_parse_errs.v[i].level;
}

sp_int sp_noko_parse_error_line(sp_int i)
{
	return sp_nk_parse_errs.v[i].line;
}

sp_int sp_noko_parse_error_column(sp_int i)
{
	return sp_nk_parse_errs.v[i].column;
}

const char *sp_noko_parse_error_message(sp_int i)
{
	return sp_nk_parse_errs.v[i].message;
}
