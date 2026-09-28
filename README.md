# nokogiri (spinel-nokogiri)

A subset of the [nokogiri](https://nokogiri.org) gem (1.19.x) for Spinel,
over **libxml2 2.13.9 with Nokogiri's own patches** — the library Nokogiri
itself packages — carried in this repository and compiled with it. The
require string is `nokogiri` and the names are the gem's, so code written
against the gem resolves here unchanged:

```ruby
require "nokogiri"

doc = Nokogiri::HTML(html)
doc.at_css("meta[property='og:image']")&.attributes&.[]("content")&.text
doc.css('[rel~="webmention"]').css("[href]").attribute("href").value
doc.xpath("//*/meta[starts-with(@property, \"og:\") or starts-with(@name, \"og:\")]")

doc.css("h1, h2, h3").each { |h| h.name = "strong" }
doc.css("a").each { |a| a[:rel] = "ugc" }
link = doc.create_element("a")
link["href"] = img["src"]
link.content = img["alt"]          # escaped: "<" stays text
img.replace(link)
doc.at_css("body").inner_html
```

## Why carry libxml2

Parsing and serialization are where a port would otherwise drift. The
bytes an app shows are libxml2's re-serialization of the parsed tree —
`<br />` comes back as `<br>`, `checked=""` as `checked`, entities are
decoded or kept by libxml2's rules — so the only way to match Nokogiri
byte for byte is Nokogiri's libxml2. The system one is not it: Nokogiri
1.19.4 packages 2.13.9 with six patches, macOS ships 2.9.13 and Ubuntu
24.04 2.9.14, and the HTML parser and serializer changed a great deal
between 2.9 and 2.13. So the package carries 2.13.9, with the six patches
from Nokogiri's `patches/libxml2/` applied (they are also in
`libxml2/patches/`, for provenance).

For HTML5 it carries the other parser Nokogiri vendors: **gumbo**, as
Nokogiri 1.19.4 ships it in `gumbo-parser/src` (it began as nokogumbo's),
unedited in `gumbo/`. Nokogiri's `gumbo.c` rebuilds gumbo's tree as a
libxml2 tree and its `html_standard_serialize` writes one back out by the
HTML standard's rules; both are C over libxml2, and are ported into
`sp_nokogiri.c` off the Ruby C API, so an HTML5 document is the same
libxml2 tree everything else here (XPath, CSS, editing) works on.

## How it is built

- `libxml/` is libxml2's public headers, at the package root, so the
  sources' `#include <libxml/…>` resolves through `spin`'s
  `-I <package>` unchanged. `libxml2/` is the 42 sources this
  configuration compiles, with `libxml.h`, `timsort.h`, the private
  headers in `libxml2/private/`, and the `config.h` configure generated.
  The configuration is Nokogiri's (`--with-c14n --with-debug
  --with-threads --with-legacy`, no python, no readline) except that
  zlib, lzma, ICU and iconv are off — see "Subset" — and the generated
  `config.h` and `xmlversion.h` are byte-identical on macOS and Ubuntu, so
  one committed copy serves both. No source file is edited beyond
  Nokogiri's patches.
- A node holds a `native_struct` (`NokoNodeRef`): one `xmlNode` plus the
  owner of its document. libxml2 frees a document with its tree; a node
  unlinked from it (`replace`, `remove`) is listed with the document and
  freed when the document is, if it is still parentless then — Nokogiri's
  own rule, so a Ruby handle to a replaced node stays valid. The owner
  counts every handle, under one mutex (finalizers may run on a GC
  sweeper thread). `test/finalizer.rb` checks that three thousand
  documents edited the way lobsters edits them are released.
- Inserting a text node copies it, as Nokogiri does: libxml2 merges
  adjacent text nodes on insert and would free the inserted one out from
  under its handle.
- `to_html` is `xmlSaveTree` through a save context with the gem's
  `SaveOptions::DEFAULT_HTML` and the document's encoding; `inner_html` is
  the children's `to_html`, joined, as in the gem.
- XPath is libxml2's. CSS selectors are translated to XPath in Ruby, the
  way the gem's CSS engine writes them (`Nokogiri::CSS.xpath_for`), with
  the gem's search contexts: `//` from a document, `.//` from a node, and
  `.//` plus `self::` from a node set (so `set.css("[href]")` finds a node
  of the set that has the attribute itself). A comma list is one XPath
  union, which libxml2 answers in document order, as the gem does.

## Subset vs nokogiri

- `Nokogiri::HTML` / `HTML4::Document.parse` (a String, UTF-8,
  `ParseOptions::DEFAULT_HTML`); `XML::Node`: `name` (and `=`), `[]`,
  `[]=`, `key?`, `attribute`, `attributes`, `remove_attribute`, `content`
  / `text` (and `content=`), `children`, `child`, `parent`,
  `next_sibling`, `previous_sibling`, `document`, `add_child`,
  `add_previous_sibling`, `add_next_sibling`, `replace` (node or set),
  `unlink` / `remove`, `css`, `at_css`, `xpath`, `at_xpath`, `search`,
  `at`, `to_html`, `inner_html`; `Document#root`, `create_element`,
  `create_text_node`, `encoding`, `meta_encoding`;
  `Nokogiri::HTML.fragment` / `HTML4::DocumentFragment` (parsed as the gem
  parses a fragment without a context, and reparented into a real fragment
  node, which is what libxml2's serializer keys its newlines on);
  `Nokogiri::XML` / `XML::Document.parse` (a String; the declaration
  names the encoding; `ParseOptions::DEFAULT_XML`, or an Integer, or the
  block form `{ |config| config.strict.noblanks }`): a malformed document
  is recovered with its `errors` (`XML::SyntaxError`: `level`, `line`,
  `column`, the gem's `to_s`) unless strict, which raises; `Document#xml?`,
  `html?`, `version`, `remove_namespaces!`; `Node#to_xml`, and `to_s` as
  XML in an XML document; `cdata?`, `processing_instruction?`.
- Namespaces: `Node#namespace` (`XML::Namespace`: `prefix`, `href`),
  `namespaces`, `namespace_definitions`; `xpath` binds the root's
  namespaces by default (a default namespace is `xmlns:`), or a Hash
  given after the paths; CSS puts an unprefixed element name in the
  default namespace and reads `ns|name`, as the gem does; a reparented
  element is relinked into the namespaces where it lands (the gem's
  `relink_namespace`, without the opt-in `namespace_inheritance`).
- Markup wherever a node goes, parsed in the context of where it is
  going (the gem's `Node#parse`, libxml2's `xmlParseInNodeContext`, so
  `tr.add_child("<td>…")` makes a cell): `add_child`, `<<`,
  `add_previous_sibling`, `add_next_sibling`, `before`, `after`,
  `prepend_child`, `replace`, `swap`, `children=`, `inner_html=`,
  `wrap`; also `Node#parse`, `Node#fragment`, `Document#fragment`,
  `Nokogiri::XML.fragment` / `XML::DocumentFragment`, and HTML fragments
  with a context. A node from another document is copied in and a text
  node is moved as a copy, as the gem does, and the handle passed then
  holds the node that went in; `dup`.
- More of `Node`: `ancestors` (and with a selector), `traverse`,
  `matches?`, `elements` / `element_children`, `first_element_child`,
  `last_element_child`, `next_element`, `previous_element`, `classes`,
  `add_class`, `append_class`, `remove_class` (a String or an Array),
  `each` (name, value), `values`, `value?`, `delete`, `<<`, `path`,
  `line`, `blank?`.
- `NodeSet` is the gem's Enumerable one — `select`, `reject`,
  `find_all`, `sort_by`, `group_by`, `partition`, `take`, `drop`,
  `first(n)` … answer Arrays, as they do in the gem — with `each`,
  `each_with_index`, `each_with_object`, `each_slice`, `map`,
  `flat_map`, `filter_map`, `find` / `detect`, `find_index`,
  `index(node)`, `include?`, `any?`, `all?`, `none?`, `count`, `min_by`,
  `max_by`, `inject` / `reduce` (with an initial value), `[]` (an index,
  start and length, or a range), `slice`, `first`, `last`, `length`,
  `empty?`, `reverse`; as a set, `|` / `+`, `&`, `-`, `==`, `push` /
  `<<`, `delete`, `pop`, `shift`, `children`; searching, `css`, `xpath`,
  `at_css`, `at_xpath`, `search`, `at`, `filter(selector)`; over every
  member, `attr` / `set`, `remove_attr`, `add_class`, `append_class`,
  `remove_class`, `before`, `after`, `remove` / `unlink`; and `text`,
  `to_html`, `to_xml`, `inner_html`.
- CSS, written as the gem's XPathVisitor writes it: type, universal and
  `ns|name` selectors, `#id`, `.class`, attribute selectors (`[a]`,
  `[a=v]`, `!=`, `~=`, `|=`, `^=`, `$=`, `*=`), comma lists; the
  descendant, child, adjacent (`+`) and general sibling (`~`)
  combinators, leading ones too (`node.css("> li")`); the pseudo-classes
  `:first-child`, `:last-child`, `:only-child`, `:first-of-type`,
  `:last-of-type`, `:only-of-type`, `:nth-child()`, `:nth-last-child()`,
  `:nth-of-type()`, `:nth-last-of-type()` (an integer, `odd`, `even` or
  `an+b`), `:not()`, `:has()`, `:contains()`, `:empty`, `:parent`,
  `:root`, and jQuery's `:first`, `:last`, `:eq()`, `:nth()`, `:gt()`.
  The pseudo-classes the gem leaves to a custom handler (`:even`, `:odd`,
  `:lt()`, `:checked`, `:disabled`, …) raise the gem's own
  `XPath::SyntaxError` ("Unregistered function"). Where the gem's parser
  would silently drop part of a selector — `:not(p.x)` becomes
  `:not(p)`, `:has(a, b)` becomes `:has(a)` — this raises
  `Nokogiri::CSS::SyntaxError` instead; so do pseudo-elements (`::before`)
  and `*|name`.
- `Nokogiri::HTML5` / `HTML5.parse` / `HTML5::Document.parse` (a
  String, UTF-8) with gumbo's limits as keywords (`max_attributes`,
  `max_errors`, `max_tree_depth`, `parse_noscript_content_as_text`; a
  limit hit raises `ArgumentError`, as in the gem); `quirks_mode`;
  `errors` (gumbo's caret diagnostics, kept up to `max_errors`, none by
  default); SVG and MathML elements in their namespaces; the HTML
  standard's serialization for `to_html` / `to_s` / `inner_html`; CSS
  over any namespace (`*:name`, as the gem writes it for HTML5);
  `HTML5.fragment` / `HTML5::DocumentFragment` in the context of nothing
  (body), a tag name (`"tr"`, `"svg"`, `"math:mi"`) or a node (form
  ancestors, annotation-xml encodings and the document's quirks mode
  included); and markup edited in an HTML5 document is parsed by gumbo
  in context (`tr.add_child("<td>…")`). `Node#document` answers the class
  the document was made as (HTML5, HTML4 or XML).
- What Loofah and rails-html-sanitizer stand on: a subclass of a
  document parses as itself (`MyDoc.parse` answers a `MyDoc`), and
  `Document.new` makes an empty one (XML, HTML4, HTML5), with
  `encoding=`; `Node#attribute_nodes`, `attribute` and `attributes` answer
  live `XML::Attr` nodes (`name` / `node_name`, `value` / `value=` as the
  gem's `set_value` encodes it, `namespace`, `remove`), and
  `remove_attribute` unlinks rather than frees, so a held attribute stays
  valid; `XML::Text.new(string, doc)`, `Document#create_cdata`,
  `Node#encode_special_chars`, `parent=`, `type` and the node-type
  constants on `XML::Node`; a fragment's `xpath` runs from the fragment
  node (`fragment.at_xpath("./body")`), and it answers `xml?`, `dup` and
  `to_html(encoding: "UTF-8")` (any other encoding raises
  `NotImplementedError`); `Nokogiri::VERSION` (`"1.19.4"`),
  `uses_gumbo?`, `jruby?` and `VersionInfo.instance.libxml2?`.
- Not yet: an IO or file argument to a parse, a non-UTF-8 String given to
  `HTML5` (the gem re-encodes one), a block to `HTML5` parse,
  `preserve_newline` and other `write_to` options, `HTML5::Builder`, `create_element`'s
  contents and attributes arguments, DTDs and validation, XPath variable
  bindings and custom functions, an XPath expression that is not a node
  set, `Builder`, `Node.new`, custom pseudo-class handlers, a block to
  `Node#parse` or a fragment's constructor, `NodeSet#wrap`, and
  `NodeSet#index`'s block form (use `find_index`; matz/spinel#5097). A
  fragment's `errors` are its own parse's; the gem also replaces the
  document's with them.
- libxml2 is built **without iconv**: it decodes UTF-8, UTF-16, ISO-8859-1
  and ASCII itself, which covers a UTF-8 String; a document declaring
  another charset is decoded differently from the gem. Without zlib and
  lzma, which only matter for reading compressed files.

## Requirements

A C compiler; nothing else — libxml2 and gumbo are compiled from
`libxml2/` and `gumbo/` with the package (a few seconds, once; `spin`
caches the objects).

Spinel 5fc203aa or later (matz/spinel#5075 and #5076: before them, a
multiple assignment to an index target — `link["href"], title, alt = …`,
which lobsters' Markdowner writes — dropped the write, and `NodeSet#[]` was
typed from an unrelated `[]` call and did not compile).

## Tests

```sh
spin test          # compiled port against the committed snapshots
sh oracle/run.sh   # the SAME test files under CRuby with the real gem
```

- `test/markdowner_test.rb` — lobsters' Markdowner post-processing over
  3404 HTML documents: the commonmarker gem's renders of the CommonMark
  and GFM spec examples and of lobsters' fake data, safe and `unsafe`.
- `test/queries_test.rb` — og: meta lookups, webmention discovery,
  campfire's Opengraph XPath, the CSS subset, attributes, `content=`
  escaping, `replace` with a set, whole-document serialization.
- `test/fragment_test.rb` — fragments (campfire's turbo-stream test
  helper) and `meta_encoding` (campfire's Opengraph).
- `test/css_test.rb` — the combinators and pseudo-classes, answer by
  answer, in HTML and in a default-namespace XML document.
- `test/nodeset_test.rb` — NodeSet as Enumerable, as a set, and bulk
  edits; the Node conveniences.
- `test/markup_test.rb` — markup in every editing method, in context
  (a `<td>` under a `<tr>`); fragments with and without a context;
  nodes moved between documents and text nodes moved; XML with
  namespaces and a malformed fragment.
- `test/xml_test.rb` — XML documents: an Atom feed (default and prefixed
  namespaces, CSS and XPath over them), RSS, CDATA / comment / PI nodes,
  the XML serializer, errors recovered and strict, `remove_namespaces!`,
  namespace relinking.
- `test/html5_test.rb` — HTML5: tree construction (misnesting, foster
  parenting), SVG and MathML, serialization, quirks modes, errors and
  limits, fragments in each kind of context, markup edited in context,
  CSS.
- `test/html5_corpus_test.rb` — the Markdowner corpus's 3404 documents
  as HTML5 documents and fragments, with their error counts, and edited.
- `test/loofah_surface_test.rb` — the surface above: subclasses and empty
  documents, attribute nodes edited and removed, text and CDATA nodes,
  fragments searched from the fragment node and copied.
- `test/finalizer.rb` — the owners, released (HTML, HTML5 and XML documents,
  markup edits, and nodes carried from throwaway documents into a kept
  one).

The snapshots are the gem's answers (Nokogiri 1.19.4), frozen; no
hand-authored expectations.

## License

MIT, like the gem. `libxml2/` and `libxml/` are libxml2's, under its MIT
license (`libxml2/Copyright`); `libxml2/patches/` are Nokogiri's (MIT).
`gumbo/` is gumbo's, under the Apache License 2.0 (`gumbo/LICENSE`, the
text from Nokogiri's `LICENSE-DEPENDENCIES.md`). The parts of
`sp_nokogiri.c` ported from Nokogiri's `gumbo.c` and `xml_node.c` are
Nokogiri's (`gumbo.c` is Apache 2.0, from nokogumbo).
