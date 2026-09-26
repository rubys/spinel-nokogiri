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
  `create_text_node`, `encoding`; `NodeSet` (`each`, `map`, `select`,
  `find`, `find_index`, `first`, `last`, `[]`, `length`, `empty?`, `css`,
  `xpath`, `attribute`, `text`, `to_html`, `inner_html`, `remove`).
- CSS: type and universal selectors, `#id`, `.class`, attribute
  selectors (`[a]`, `[a=v]`, `~=`, `|=`, `^=`, `$=`, `*=`), comma lists,
  descendant and child combinators. Anything else (pseudo-classes,
  sibling combinators, namespaces) raises `Nokogiri::CSS::SyntaxError`
  rather than guessing.
- Not yet: `Nokogiri::HTML5` (the gem's vendored gumbo parser — the next
  version), `Nokogiri::XML` documents, `DocumentFragment`, `Builder`,
  `Node.new`, moving nodes between documents.
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
- `test/finalizer.rb` — the owners, released.

The snapshots are the gem's answers (Nokogiri 1.19.4), frozen; no
hand-authored expectations.

## License

MIT, like the gem. `libxml2/` and `libxml/` are libxml2's, under its MIT
license (`libxml2/Copyright`); `libxml2/patches/` are Nokogiri's (MIT).
