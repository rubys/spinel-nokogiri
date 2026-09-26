# nokogiri for Spinel — a subset of the nokogiri gem (1.19.x) over libxml2
# 2.13.9 with Nokogiri's own patches, carried in libxml2/ and bound through
# sp_nokogiri.c. The require string is "nokogiri" and the names are the
# gem's, so code written against the gem resolves here unchanged.
#
# Parsing, XPath and serialization are libxml2's own code, as in the gem —
# the same library at the same version with the same patches — so a
# document round-trips to the gem's bytes by construction. What is ported
# in Ruby is the gem's Ruby: the node API, NodeSet, and the translation of
# CSS selectors to XPath (for the subset below; a selector outside it
# raises rather than guessing).

module NokogiriExt
  ffi_func :sp_noko_out,            [], :str
  ffi_func :sp_noko_live_documents, [], :int
end

# The native half of a node: one xmlNode plus the owner of its document
# (sp_nokogiri.c). Its own top-level name, for the reason spinel-ruby-vips
# gives: a native class is keyed by its last segment, so a native
# `Nokogiri::XML::Node` would merge with any other `Node` in the program.
module NokogiriNodePackage
  native_struct "NokoNodeRef", "sp_NokoNode", "sp_NokoNode_fin"
  native_new [], "sp_NokoNode_new"

  native_method :__present?,         [], :bool,                     "sp_NokoNode_present_p"
  native_method :__same?,            [:any], :bool,                 "sp_NokoNode_same_p"
  native_method :__same_document?,   [:any], :bool,                 "sp_NokoNode_same_document_p"
  native_method :__parse_html,       [:string, :string, :int], :self, "sp_NokoNode_parse_html"
  native_method :__type,             [], :int,                      "sp_NokoNode_type"
  native_method :__name,             [], :string,                   "sp_NokoNode_name"
  native_method :__first_child,      [], :self,                     "sp_NokoNode_first_child"
  native_method :__last_child,       [], :self,                     "sp_NokoNode_last_child"
  native_method :__next_sibling,     [], :self,                     "sp_NokoNode_next_sibling"
  native_method :__previous_sibling, [], :self,                     "sp_NokoNode_previous_sibling"
  native_method :__parent,           [], :self,                     "sp_NokoNode_parent"
  native_method :__document,         [], :self,                     "sp_NokoNode_document"
  native_method :__content,          [], :int,                      "sp_NokoNode_content"
  native_method :__has_attr?,        [:string], :bool,              "sp_NokoNode_has_attr"
  native_method :__attr,             [:string], :int,               "sp_NokoNode_attr"
  native_method :__attr_count,       [], :int,                      "sp_NokoNode_attr_count"
  native_method :__attr_name,        [:int], :string,               "sp_NokoNode_attr_name"
  native_method :__set_name,         [:string], :void,              "sp_NokoNode_set_name"
  native_method :__set_attr,         [:string, :string], :void,     "sp_NokoNode_set_attr"
  native_method :__remove_attr,      [:string], :void,              "sp_NokoNode_remove_attr"
  native_method :__set_content,      [:string], :void,              "sp_NokoNode_set_content"
  native_method :__create_element,   [:string], :self,              "sp_NokoNode_create_element"
  native_method :__create_text,      [:string], :self,              "sp_NokoNode_create_text"
  native_method :__create_fragment,  [], :self,                     "sp_NokoNode_create_fragment"
  native_method :__unlink,           [], :void,                     "sp_NokoNode_unlink"
  native_method :__add_previous_sibling, [:any], :self,             "sp_NokoNode_add_previous_sibling"
  native_method :__add_next_sibling, [:any], :self,                 "sp_NokoNode_add_next_sibling"
  native_method :__add_child,        [:any], :self,                 "sp_NokoNode_add_child"
  native_method :__xpath,            [:string], :int,               "sp_NokoNode_xpath"
  native_method :__xpath_result,     [:int], :self,                 "sp_NokoNode_xpath_result"
  native_method :__serialize,        [:int], :int,                  "sp_NokoNode_serialize"
  native_method :__encoding,         [], :string,                   "sp_NokoNode_encoding"
end

module Nokogiri
  # The gem's Nokogiri::HTML(string) — an HTML4 document.
  def self.HTML(html)
    HTML4::Document.parse(html)
  end

  def self.HTML4(html)
    HTML4::Document.parse(html)
  end

  module XML
    # libxml2's xmlElementType values.
    ELEMENT_NODE = 1
    ATTRIBUTE_NODE = 2
    TEXT_NODE = 3
    CDATA_SECTION_NODE = 4
    COMMENT_NODE = 8
    DOCUMENT_NODE = 9
    HTML_DOCUMENT_NODE = 13
    DTD_NODE = 14

    class ParseOptions
      RECOVER = 1 << 0
      NOERROR = 1 << 5
      NOWARNING = 1 << 6
      NONET = 1 << 11
      BIG_LINES = 1 << 22
      DEFAULT_HTML = RECOVER | NOERROR | NOWARNING | NONET | BIG_LINES
    end

    module XPath
      class SyntaxError < StandardError
      end
    end

    class Node
      module SaveOptions
        FORMAT = 1
        NO_DECLARATION = 2
        NO_EMPTY_TAGS = 4
        NO_XHTML = 8
        AS_XHTML = 16
        AS_XML = 32
        AS_HTML = 64
        DEFAULT_HTML = FORMAT | NO_DECLARATION | NO_EMPTY_TAGS | AS_HTML
      end

      # A handle the native side made. Nokogiri makes nodes through
      # Document#create_element, not Node.new.
      def initialize(ref)
        @ref = ref
      end

      def __ref
        @ref
      end

      # A handle, or nil when it holds no node.
      def self.wrap(ref)
        ref.__present? ? Node.new(ref) : nil
      end

      def ==(other)
        other.is_a?(Node) && @ref.__same?(other.__ref)
      end

      def node_type
        @ref.__type
      end

      def element?
        node_type == ELEMENT_NODE
      end

      def text?
        node_type == TEXT_NODE
      end

      def comment?
        node_type == COMMENT_NODE
      end

      def document?
        node_type == HTML_DOCUMENT_NODE || node_type == DOCUMENT_NODE
      end

      def name
        return "text" if text?
        return "comment" if comment?
        @ref.__name
      end

      def name=(n)
        @ref.__set_name(n.to_s)
      end

      def document
        Document.new(@ref.__document)
      end

      def parent
        Node.wrap(@ref.__parent)
      end

      def next_sibling
        Node.wrap(@ref.__next_sibling)
      end

      def previous_sibling
        Node.wrap(@ref.__previous_sibling)
      end

      def next
        next_sibling
      end

      def previous
        previous_sibling
      end

      def children
        set = []
        c = Node.wrap(@ref.__first_child)
        while c
          set << c
          c = c.next_sibling
        end
        NodeSet.new(set)
      end

      def child
        Node.wrap(@ref.__first_child)
      end

      def element_children
        NodeSet.new(children.to_a.select { |c| c.element? })
      end

      # ---- attributes ------------------------------------------------------

      def [](key)
        k = key.to_s
        return nil unless @ref.__has_attr?(k)
        @ref.__attr(k)
        NokogiriExt.sp_noko_out
      end

      def []=(key, value)
        @ref.__set_attr(key.to_s, value.to_s)
        value
      end

      def get_attribute(key)
        self[key]
      end

      def set_attribute(key, value)
        self[key] = value
      end

      def key?(key)
        @ref.__has_attr?(key.to_s)
      end

      def has_attribute?(key)
        key?(key)
      end

      def remove_attribute(key)
        @ref.__remove_attr(key.to_s)
        nil
      end

      def attribute(key)
        v = self[key]
        v.nil? ? nil : Attr.new(key.to_s, v)
      end

      # name => Attr, in document order.
      def attributes
        h = {}
        i = 0
        n = @ref.__attr_count
        while i < n
          k = @ref.__attr_name(i)
          h[k] = Attr.new(k, self[k].to_s)
          i += 1
        end
        h
      end

      def keys
        attributes.keys
      end

      # ---- content -------------------------------------------------------

      def content
        @ref.__content
        NokogiriExt.sp_noko_out
      end

      def text
        content
      end

      def inner_text
        content
      end

      # The gem's: the special characters are encoded, so "<" stays text.
      def content=(s)
        @ref.__set_content(s.to_s)
        s
      end

      # ---- editing -------------------------------------------------------

      def add_previous_sibling(node)
        check_same_document(node)
        Node.wrap(@ref.__add_previous_sibling(node.__ref))
      end

      def add_next_sibling(node)
        check_same_document(node)
        Node.wrap(@ref.__add_next_sibling(node.__ref))
      end

      def before(node)
        add_previous_sibling(node)
        self
      end

      def after(node)
        add_next_sibling(node)
        self
      end

      def add_child(node)
        check_same_document(node)
        Node.wrap(@ref.__add_child(node.__ref))
      end

      def unlink
        @ref.__unlink
        self
      end

      def remove
        unlink
      end

      # The gem's replace: a NodeSet goes in node by node before this one,
      # a node takes this one's place; either way this one is unlinked.
      def replace(node_or_set)
        raise "Cannot replace a node with no parent" if parent.nil?
        if node_or_set.is_a?(NodeSet)
          node_or_set.to_a.each { |n| add_previous_sibling(n) }
        else
          add_previous_sibling(node_or_set)
        end
        unlink
        node_or_set
      end

      # ---- searching -----------------------------------------------------

      def xpath(*paths)
        Search.xpath(self, paths.join(" | "))
      end

      def at_xpath(*paths)
        xpath(*paths).first
      end

      def css(*rules)
        Search.xpath(self, CSS.translate(rules.join(", "), css_contexts))
      end

      def at_css(*rules)
        css(*rules).first
      end

      # The gem's search: XPath when the rule looks like one, CSS otherwise.
      def search(*rules)
        r = rules.join(", ")
        Search.looks_like_xpath?(r) ? xpath(r) : css(r)
      end

      def at(*rules)
        search(*rules).first
      end

      def css_contexts
        document? ? ["//"] : [".//"]
      end

      # ---- serialization -------------------------------------------------

      def to_html
        @ref.__serialize(SaveOptions::DEFAULT_HTML)
        NokogiriExt.sp_noko_out
      end

      def to_s
        to_html
      end

      def inner_html
        children.to_a.map { |c| c.to_html }.join
      end

      private

      def check_same_document(node)
        unless @ref.__same_document?(node.__ref)
          raise ArgumentError, "nokogiri (spinel): moving a node between documents is not supported"
        end
        nil
      end
    end

    class Document < Node
      def root
        c = child
        while c && !c.element?
          c = c.next_sibling
        end
        c
      end

      def create_element(name)
        Node.wrap(@ref.__create_element(name.to_s))
      end

      def create_text_node(text)
        Node.wrap(@ref.__create_text(text.to_s))
      end

      def encoding
        e = @ref.__encoding
        e == "" ? nil : e
      end

      def name
        "document"
      end
    end

    class Attr
      def initialize(name, value)
        @name = name
        @value = value
      end

      def name
        @name
      end

      def value
        @value
      end

      def content
        @value
      end

      def text
        @value
      end

      def to_s
        @value
      end
    end

    class NodeSet
      def initialize(nodes)
        @nodes = nodes
      end

      def to_a
        @nodes
      end

      def each(&block)
        @nodes.each(&block)
        self
      end

      def map(&block)
        @nodes.map(&block)
      end

      def select(&block)
        NodeSet.new(@nodes.select(&block))
      end

      def find(&block)
        @nodes.find(&block)
      end

      def find_index(&block)
        @nodes.find_index(&block)
      end

      def length
        @nodes.length
      end

      def size
        @nodes.length
      end

      def count
        @nodes.length
      end

      def empty?
        @nodes.empty?
      end

      def first
        @nodes.first
      end

      def last
        @nodes.last
      end

      def [](i)
        @nodes[i]
      end

      # The gem's NodeSet#css: each node searched with ".//" AND "self::",
      # so a node of the set that itself matches is found.
      def css(*rules)
        xp = CSS.translate(rules.join(", "), [".//", "self::"])
        out = []
        @nodes.each do |n|
          Search.xpath(n, xp).to_a.each { |m| out << m unless out.any? { |o| o == m } }
        end
        NodeSet.new(out)
      end

      def xpath(*paths)
        expr = paths.join(" | ")
        out = []
        @nodes.each do |n|
          Search.xpath(n, expr).to_a.each { |m| out << m unless out.any? { |o| o == m } }
        end
        NodeSet.new(out)
      end

      def at_css(*rules)
        css(*rules).first
      end

      def search(*rules)
        r = rules.join(", ")
        Search.looks_like_xpath?(r) ? xpath(r) : css(r)
      end

      # The gem's NodeSet#attribute(name): the first node's.
      def attribute(key)
        n = @nodes.first
        n.nil? ? nil : n.attribute(key)
      end

      def attr(key)
        attribute(key)
      end

      def text
        @nodes.map { |n| n.text }.join
      end

      def to_html
        @nodes.map { |n| n.to_html }.join
      end

      def to_s
        to_html
      end

      def inner_html
        @nodes.map { |n| n.inner_html }.join
      end

      def remove
        @nodes.each { |n| n.unlink }
        self
      end
    end

    # XPath evaluation, shared by Node and NodeSet.
    module Search
      def self.xpath(node, expr)
        n = node.__ref.__xpath(expr)
        raise Nokogiri::XML::XPath::SyntaxError, "ERROR: Invalid expression: #{expr}" if n == -1
        out = []
        i = 0
        while i < n
          r = Node.wrap(node.__ref.__xpath_result(i))
          out << r unless r.nil?
          i += 1
        end
        NodeSet.new(out)
      end

      def self.looks_like_xpath?(rule)
        rule.start_with?("/") || rule.start_with?("./") || rule.start_with?("self::")
      end
    end
  end

  # CSS selectors to XPath, the way the gem's CSS engine writes them
  # (Nokogiri::CSS.xpath_for), for the subset real apps use: type and
  # universal selectors, `#id`, `.class`, attribute selectors (`[a]`,
  # `[a=v]`, `~=`, `|=`, `^=`, `$=`, `*=`), comma lists, and the
  # descendant and child combinators. Anything else raises.
  module CSS
    class SyntaxError < StandardError
    end

    def self.xpath_for(selector)
      translate(selector, ["//"]).split(" | ")
    end

    # The whole selector list as one XPath union: libxml2 sorts a union into
    # document order, which is what the gem answers for a comma list.
    def self.translate(selector, contexts)
      parts = []
      split_list(selector).each do |sel|
        body = one(sel.strip)
        contexts.each { |ctx| parts << (ctx + body) }
      end
      parts.join(" | ")
    end

    # Splits on commas outside quotes and brackets.
    def self.split_list(selector)
      out = []
      cur = +""
      quote = ""
      depth = 0
      selector.each_char do |ch|
        if quote != ""
          quote = "" if ch == quote
          cur << ch
        elsif ch == "'" || ch == "\""
          quote = ch
          cur << ch
        elsif ch == "["
          depth += 1
          cur << ch
        elsif ch == "]"
          depth -= 1
          cur << ch
        elsif ch == "," && depth == 0
          out << cur
          cur = +""
        else
          cur << ch
        end
      end
      out << cur
      out
    end

    # One complex selector: compounds joined by descendant (" " → "//") or
    # child (">" → "/") combinators.
    def self.one(sel)
      raise SyntaxError, "nokogiri (spinel): empty CSS selector" if sel.empty?
      out = +""
      cur = +""
      quote = ""
      depth = 0
      comb = ""
      sel.each_char do |ch|
        if quote != ""
          quote = "" if ch == quote
          cur << ch
        elsif ch == "'" || ch == "\""
          quote = ch
          cur << ch
        elsif ch == "["
          depth += 1
          cur << ch
        elsif ch == "]"
          depth -= 1
          cur << ch
        elsif depth == 0 && (ch == " " || ch == ">")
          unless cur.empty?
            out << compound(cur)
            cur = +""
          end
          comb = ch == ">" ? ">" : (comb == ">" ? ">" : " ")
        else
          if comb != ""
            out << (comb == ">" ? "/" : "//")
            comb = ""
          end
          cur << ch
        end
      end
      out << compound(cur) unless cur.empty?
      out
    end

    # tag or * followed by #id, .class and [attr…] parts.
    def self.compound(c)
      i = 0
      tag = +""
      while i < c.length && c[i] != "#" && c[i] != "." && c[i] != "["
        tag << c[i]
        i += 1
      end
      tag = +"*" if tag.empty?
      unless tag == "*" || tag.match?(/\A[A-Za-z][A-Za-z0-9_-]*\z/)
        raise SyntaxError, "nokogiri (spinel): unsupported CSS selector: #{c}"
      end
      preds = +""
      while i < c.length
        if c[i] == "#" || c[i] == "."
          j = i + 1
          j += 1 while j < c.length && c[j] != "#" && c[j] != "." && c[j] != "["
          word = c[(i + 1)...j]
          if c[i] == "#"
            preds << "[@id='#{word}']"
          else
            preds << "[contains(concat(' ',normalize-space(@class),' '),' #{word} ')]"
          end
          i = j
        elsif c[i] == "["
          j = c.index("]", i)
          raise SyntaxError, "nokogiri (spinel): unterminated attribute selector: #{c}" if j.nil?
          preds << "[" << attribute(c[(i + 1)...j]) << "]"
          i = j + 1
        else
          raise SyntaxError, "nokogiri (spinel): unsupported CSS selector: #{c}"
        end
      end
      tag + preds
    end

    # One attribute test. The value keeps the quotes it was written with,
    # as the gem's does (`[a='v']` → `@a='v'`, `[a="v"]` → `@a="v"`); a bare
    # value is written with single quotes.
    def self.attribute(body)
      m = body.match(/\A\s*([A-Za-z_:][A-Za-z0-9_:.-]*)\s*(?:([~|^$*]?=)\s*(.+?))?\s*\z/)
      raise SyntaxError, "nokogiri (spinel): unsupported attribute selector: [#{body}]" if m.nil?
      name = m[1].to_s
      op = m[2]
      return "@#{name}" if op.nil?
      raw = m[3].to_s
      lit = (raw.start_with?("'") || raw.start_with?("\"")) ? raw : "'#{raw}'"
      bare = lit[1...-1]
      if op == "="
        "@#{name}=#{lit}"
      elsif op == "~="
        "contains(concat(' ',normalize-space(@#{name}),' '),' #{bare} ')"
      elsif op == "|="
        "@#{name}=#{lit} or starts-with(@#{name},concat(#{lit},'-'))"
      elsif op == "^="
        "starts-with(@#{name},#{lit})"
      elsif op == "$="
        "substring(@#{name},string-length(@#{name})-string-length(#{lit})+1,string-length(#{lit}))=#{lit}"
      else
        "contains(@#{name},#{lit})"
      end
    end
  end

  module HTML4
    class Document < XML::Document
      # The gem's HTML4::Document.parse(string): the String's own encoding
      # (UTF-8) and ParseOptions::DEFAULT_HTML.
      def self.parse(html)
        ref = NokoNodeRef.new.__parse_html(html.to_s, "UTF-8", XML::ParseOptions::DEFAULT_HTML)
        Document.new(ref)
      end

      # The gem's, verbatim in effect: a <meta charset>, else the charset of
      # a <meta http-equiv="Content-Type">, else nil.
      def meta_encoding
        meta = at_xpath("//meta[@charset]")
        return meta["charset"] unless meta.nil?
        ct = meta_content_type
        return nil if ct.nil?
        m = ct["content"].to_s.match(/charset\s*=\s*([\w-]+)/i)
        m.nil? ? nil : m[1]
      end

      private

      def meta_content_type
        xpath("//meta[@http-equiv and boolean(@content)]").find do |node|
          node["http-equiv"].to_s.match?(/\AContent-Type\z/i)
        end
      end
    end

    # The gem's HTML4 fragment, parsed as it parses one without a context:
    # the input inside `<html><body>`, and the fragment is the body's
    # children (or the body itself when the input starts with one).
    class DocumentFragment
      def initialize(document, input = "")
        tags = input.to_s
        path = tags.match?(/\A\s*?<body/i) ? "/html/body" : "/html/body/node()"
        @doc = Document.parse("<html><body>" + tags)
        @frag = XML::Node.new(@doc.__ref.__create_fragment)
        @doc.xpath(path).to_a.each { |child| @frag.add_child(child) }
      end

      def self.parse(tags)
        DocumentFragment.new(nil, tags)
      end

      def document
        @doc
      end

      def children
        @frag.children
      end

      def css(*rules)
        children.css(*rules)
      end

      def at_css(*rules)
        children.css(*rules).first
      end

      def xpath(*paths)
        children.xpath(*paths)
      end

      def search(*rules)
        children.search(*rules)
      end

      def text
        children.text
      end

      def to_html
        children.to_html
      end

      def to_s
        to_html
      end
    end

    def self.fragment(tags)
      DocumentFragment.parse(tags)
    end
  end

  HTML = HTML4
end
