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
- Not yet: `Nokogiri::HTML5` (the gem's vendored gumbo parser — the next
  version), an IO or file argument to a parse, XML fragments,
  `create_element`'s contents and attributes arguments, DTDs and
  validation, XPath variable bindings and custom functions, an XPath
  expression that is not a node set, a fragment parsed in a context
  node (so `inner_html=`, `children=`, and `wrap` / `add_child` with a
  markup String), `Builder`, `Node.new`, moving nodes between documents,
  custom pseudo-class handlers, and `NodeSet#index`'s block form (use
  `find_index`; matz/spinel#5097).
- libxml2 is built **without iconv**: it decodes UTF-8, UTF-16, ISO-8859-1
  and ASCII itself, which covers a UTF-8 String; a document declaring
  another charset is decoded differently from the gem. Without zlib and
  lzma, which only matter for reading compressed files.

## Requirements

A C compiler; nothing else — libxml2 is compiled from `libxml2/` with the
package (about ten seconds, once; `spin` caches the objects).

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
- `test/xml_test.rb` — XML documents: an Atom feed (default and prefixed
  namespaces, CSS and XPath over them), RSS, CDATA / comment / PI nodes,
  the XML serializer, errors recovered and strict, `remove_namespaces!`,
  namespace relinking.
- `test/finalizer.rb` — the owners, released (HTML and XML documents).

The snapshots are the gem's answers (Nokogiri 1.19.4), frozen; no
hand-authored expectations.

## License

MIT, like the gem. `libxml2/` and `libxml/` are libxml2's, under its MIT
license (`libxml2/Copyright`); `libxml2/patches/` are Nokogiri's (MIT).
