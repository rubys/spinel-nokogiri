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
	doc = htmlReadMemory(html, (int)strlen(html), NULL, encoding, (int)options);
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
	doc = xmlReadMemory(xml, (int)strlen(xml), NULL, *encoding ? encoding : NULL, (int)options);
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

sp_int sp_NokoNode_attr(sp_NokoNode *self, const char *name)
{
	return (sp_int)strlen(sp_nk_set_out(xmlGetProp(self->node, (const xmlChar *)name)));
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

void sp_NokoNode_remove_attr(sp_NokoNode *self, const char *name)
{
	xmlAttrPtr a = xmlHasProp(self->node, (const xmlChar *)name);
	if (a)
		xmlRemoveProp(a);
}

/* Node#content=: Nokogiri encodes the special characters and sets the
   result as the content (so "<" stays text). */
void sp_NokoNode_set_content(sp_NokoNode *self, const char *text)
{
	xmlChar *enc = xmlEncodeSpecialChars(self->node->doc, (const xmlChar *)text);
	xmlNodeSetContent(self->node, enc);
	xmlFree(enc);
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

/* The reparenting primitives Nokogiri's replace / add_* are built from.
   libxml2 MERGES adjacent text nodes when it inserts a text node next to
   one (freeing the inserted one), which would free memory a Ruby handle
   still points at; Nokogiri avoids it by inserting a copy of a text node,
   and so does this. Answers the node that is now in the tree. Both nodes
   must belong to the same document (the Ruby side checks). */
static xmlNodePtr sp_nk_insertable(sp_NokoNode *self, xmlNodePtr n)
{
	if (n->type == XML_TEXT_NODE) {
		xmlNodePtr copy = xmlDocCopyNode(n, self->owner->doc, 1);
		return copy;
	}
	xmlUnlinkNode(n);
	return n;
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

static sp_NokoNode *sp_nk_reparented(sp_NokoNode *self, xmlNodePtr r)
{
	if (r) {
		pthread_mutex_lock(&sp_nk_lock);
		sp_nk_relink(self->owner, r);
		pthread_mutex_unlock(&sp_nk_lock);
	}
	return sp_nk_wrap(self->cls_id, r, self->owner);
}

sp_NokoNode *sp_NokoNode_add_previous_sibling(sp_NokoNode *self, sp_RbVal arg)
{
	xmlNodePtr n = sp_nk_insertable(self, sp_nk_arg(arg)->node);
	return sp_nk_reparented(self, xmlAddPrevSibling(self->node, n));
}

sp_NokoNode *sp_NokoNode_add_next_sibling(sp_NokoNode *self, sp_RbVal arg)
{
	xmlNodePtr n = sp_nk_insertable(self, sp_nk_arg(arg)->node);
	return sp_nk_reparented(self, xmlAddNextSibling(self->node, n));
}

sp_NokoNode *sp_NokoNode_add_child(sp_NokoNode *self, sp_RbVal arg)
{
	xmlNodePtr n = sp_nk_insertable(self, sp_nk_arg(arg)->node);
	return sp_nk_reparented(self, xmlAddChild(self->node, n));
}

sp_bool sp_NokoNode_same_document_p(sp_NokoNode *self, sp_RbVal other)
{
	return self->owner == sp_nk_arg(other)->owner;
}

/* ---- XPath ------------------------------------------------------------- */

/* The last query's results, per thread, read out one by one. */
static SP_TLS xmlXPathObjectPtr sp_nk_xp = NULL;

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
	if (sp_nk_xp) {
		xmlXPathFreeObject(sp_nk_xp);
		sp_nk_xp = NULL;
	}
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
	sp_nk_xp = xmlXPathEvalExpression((const xmlChar *)expr, ctx);
	xmlXPathFreeContext(ctx);
	if (!sp_nk_xp)
		return -1;
	if (sp_nk_xp->type != XPATH_NODESET)
		return -2;
	return sp_nk_xp->nodesetval ? sp_nk_xp->nodesetval->nodeNr : 0;
}

sp_NokoNode *sp_NokoNode_xpath_result(sp_NokoNode *self, sp_int i)
{
	xmlNodePtr n = NULL;
	if (sp_nk_xp && sp_nk_xp->nodesetval && i >= 0 && i < sp_nk_xp->nodesetval->nodeNr)
		n = sp_nk_xp->nodesetval->nodeTab[i];
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
