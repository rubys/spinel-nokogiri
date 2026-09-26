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
#include <libxml/HTMLtree.h>
#include <libxml/entities.h>
#include <libxml/tree.h>
#include <libxml/xmlsave.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>

#include "spinel/runtime.h" /* sp_gc_alloc, sp_int, sp_bool, sp_RbVal */

/* ---- owners ------------------------------------------------------------ */

typedef struct sp_nk_owner {
	long refs;
	xmlDocPtr doc;
	xmlNodePtr *pieces;
	size_t n, cap;
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

/* Nokogiri::HTML4::Document.parse(string): htmlReadMemory with the String's
   encoding (UTF-8) and ParseOptions::DEFAULT_HTML. An empty or unparseable
   string still answers a document, as it does in Nokogiri. */
sp_NokoNode *sp_NokoNode_parse_html(sp_NokoNode *self, const char *html, const char *encoding, sp_int options)
{
	sp_nk_owner *o;
	htmlDocPtr doc = htmlReadMemory(html, (int)strlen(html), NULL, encoding, (int)options);
	if (!doc)
		doc = htmlNewDocNoDtD(NULL, NULL);
	o = (sp_nk_owner *)calloc(1, sizeof(sp_nk_owner));
	o->doc = doc;
	__atomic_add_fetch(&sp_nk_live_docs, 1, __ATOMIC_RELAXED);
	return sp_nk_wrap(self->cls_id, (xmlNodePtr)doc, o);
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

sp_NokoNode *sp_NokoNode_add_previous_sibling(sp_NokoNode *self, sp_RbVal arg)
{
	xmlNodePtr n = sp_nk_insertable(self, sp_nk_arg(arg)->node);
	xmlNodePtr r = xmlAddPrevSibling(self->node, n);
	return sp_nk_wrap(self->cls_id, r, self->owner);
}

sp_NokoNode *sp_NokoNode_add_next_sibling(sp_NokoNode *self, sp_RbVal arg)
{
	xmlNodePtr n = sp_nk_insertable(self, sp_nk_arg(arg)->node);
	xmlNodePtr r = xmlAddNextSibling(self->node, n);
	return sp_nk_wrap(self->cls_id, r, self->owner);
}

sp_NokoNode *sp_NokoNode_add_child(sp_NokoNode *self, sp_RbVal arg)
{
	xmlNodePtr n = sp_nk_insertable(self, sp_nk_arg(arg)->node);
	xmlNodePtr r = xmlAddChild(self->node, n);
	return sp_nk_wrap(self->cls_id, r, self->owner);
}

sp_bool sp_NokoNode_same_document_p(sp_NokoNode *self, sp_RbVal other)
{
	return self->owner == sp_nk_arg(other)->owner;
}

/* ---- XPath ------------------------------------------------------------- */

/* The last query's results, per thread, read out one by one. */
static SP_TLS xmlXPathObjectPtr sp_nk_xp = NULL;

/* Nokogiri installs its own error handler, so libxml2 prints nothing for a
   bad expression (the gem raises XPath::SyntaxError instead). The same
   here: the context's structured handler swallows the report, and the
   NULL result is what the Ruby side raises on. */
static void sp_nk_silent(void *ctx, const xmlError *err)
{
	(void)ctx;
	(void)err;
}

/* Evaluates `expr` with `self` as the context node. Answers the number of
   nodes, or -1 when libxml2 rejects the expression (Nokogiri raises
   Nokogiri::XML::XPath::SyntaxError), or -2 when it is not a node set. */
sp_int sp_NokoNode_xpath(sp_NokoNode *self, const char *expr)
{
	xmlXPathContextPtr ctx;
	if (sp_nk_xp) {
		xmlXPathFreeObject(sp_nk_xp);
		sp_nk_xp = NULL;
	}
	ctx = xmlXPathNewContext(self->owner->doc);
	ctx->node = self->node;
	ctx->error = sp_nk_silent;
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
