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
  ffi_func :sp_noko_xpath_error,    [], :str
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
  native_method :__parse_xml,        [:string, :string, :int], :self, "sp_NokoNode_parse_xml"
  native_method :__new_xml_document, [], :self,                     "sp_NokoNode_new_xml_document"
  native_method :__error_count,      [], :int,                      "sp_NokoNode_error_count"
  native_method :__error_level,      [:int], :int,                  "sp_NokoNode_error_level"
  native_method :__error_line,       [:int], :int,                  "sp_NokoNode_error_line"
  native_method :__error_column,     [:int], :int,                  "sp_NokoNode_error_column"
  native_method :__error_message,    [:int], :string,               "sp_NokoNode_error_message"
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
  native_method :__xpath,            [:string, :string], :int,      "sp_NokoNode_xpath"
  native_method :__xpath_result,     [:int], :self,                 "sp_NokoNode_xpath_result"
  native_method :__serialize,        [:int], :int,                  "sp_NokoNode_serialize"
  native_method :__encoding,         [], :string,                   "sp_NokoNode_encoding"
  native_method :__version,          [], :string,                   "sp_NokoNode_version"
  native_method :__namespace,        [], :int,                      "sp_NokoNode_namespace"
  native_method :__namespace_scopes, [], :int,                      "sp_NokoNode_namespace_scopes"
  native_method :__namespace_definitions, [], :int,                 "sp_NokoNode_namespace_definitions"
  native_method :__remove_namespaces, [], :void,                    "sp_NokoNode_remove_namespaces"
end

module Nokogiri
  class SyntaxError < StandardError
  end

  # The gem's Nokogiri::XML(string, url, encoding, options) — an XML
  # document, the parse options adjustable in a block.
  def self.XML(xml, url = nil, encoding = nil, options = XML::ParseOptions::DEFAULT_XML, &block)
    XML::Document.parse(xml, url, encoding, options, &block)
  end

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
    PI_NODE = 7
    COMMENT_NODE = 8
    DOCUMENT_NODE = 9
    HTML_DOCUMENT_NODE = 13
    DTD_NODE = 14

    # libxml2's xmlParserOption bits, and the gem's settable view of them
    # (`Nokogiri::XML(s) { |config| config.strict.noblanks }`).
    class ParseOptions
      STRICT = 0
      RECOVER = 1 << 0
      NOENT = 1 << 1
      DTDLOAD = 1 << 2
      DTDATTR = 1 << 3
      DTDVALID = 1 << 4
      NOERROR = 1 << 5
      NOWARNING = 1 << 6
      PEDANTIC = 1 << 7
      NOBLANKS = 1 << 8
      NONET = 1 << 11
      NOCDATA = 1 << 14
      HUGE = 1 << 19
      BIG_LINES = 1 << 22
      DEFAULT_XML = RECOVER | NONET | BIG_LINES
      DEFAULT_HTML = RECOVER | NOERROR | NOWARNING | NONET | BIG_LINES

      def initialize(options = STRICT)
        @options = options
      end

      def to_i
        @options
      end

      def options
        @options
      end

      def strict
        @options &= ~RECOVER
        self
      end

      def strict?
        @options & RECOVER == 0
      end

      def recover
        set(RECOVER)
      end

      def recover?
        @options & RECOVER != 0
      end

      def noent
        set(NOENT)
      end

      def noblanks
        set(NOBLANKS)
      end

      def nonet
        set(NONET)
      end

      def nocdata
        set(NOCDATA)
      end

      def huge
        set(HUGE)
      end

      def big_lines
        set(BIG_LINES)
      end

      private

      def set(bit)
        @options |= bit
        self
      end
    end

    # A parse error as the gem reports it: libxml2's message, its level
    # (1 warning, 2 error, 3 fatal) and where it was. to_s is the gem's
    # "line:column: LEVEL: message".
    class SyntaxError < Nokogiri::SyntaxError
      def self.build(message, level, line, column)
        e = new(message)
        e.__located(message, level, line, column)
        e
      end

      def __located(message, level, line, column)
        @text = message
        @level = level
        @line = line
        @column = column
        nil
      end

      def level
        @level
      end

      def line
        @line
      end

      def column
        @column
      end

      def to_s
        parts = []
        parts << "#{@line}:#{@column}" unless (@line.nil? || @line == 0) && (@column.nil? || @column == 0)
        lv = @level == 3 ? "FATAL" : (@level == 2 ? "ERROR" : (@level == 1 ? "WARNING" : nil))
        parts << lv unless lv.nil?
        parts << @text.to_s
        parts.join(": ")
      end

      def message
        to_s
      end
    end

    module XPath
      class SyntaxError < XML::SyntaxError
      end
    end

    # A namespace a node is in or declares: its prefix (nil for a default
    # namespace) and href.
    class Namespace
      def initialize(prefix, href)
        @prefix = prefix
        @href = href
      end

      def prefix
        @prefix
      end

      def href
        @href
      end

      # The native side's "prefix\thref" lines.
      def self.lines(text)
        out = []
        text.split("\n").each do |line|
          tab = line.index("\t")
          next if tab.nil?
          pre = line[0...tab]
          out << Namespace.new(pre.empty? ? nil : pre, line[(tab + 1)..])
        end
        out
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
        DEFAULT_XML = FORMAT | AS_XML
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

      def cdata?
        node_type == CDATA_SECTION_NODE
      end

      def processing_instruction?
        node_type == PI_NODE
      end

      def document?
        node_type == HTML_DOCUMENT_NODE || node_type == DOCUMENT_NODE
      end

      def name
        return "text" if text?
        return "comment" if comment?
        return "#cdata-section" if cdata?
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

      # ---- namespaces ----------------------------------------------------

      def namespace
        @ref.__namespace
        Namespace.lines(NokogiriExt.sp_noko_out).first
      end

      # The gem's: every namespace in scope, as "xmlns" / "xmlns:prefix"
      # => href, innermost first.
      def namespaces
        h = {}
        @ref.__namespace_scopes
        Namespace.lines(NokogiriExt.sp_noko_out).each do |ns|
          h[ns.prefix.nil? ? "xmlns" : "xmlns:" + ns.prefix.to_s] = ns.href
        end
        h
      end

      def namespace_definitions
        @ref.__namespace_definitions
        Namespace.lines(NokogiriExt.sp_noko_out)
      end

      # ---- searching -----------------------------------------------------

      # The gem's xpath(*paths, namespace_bindings): with no bindings, the
      # root's namespaces (so a document's default namespace is `xmlns:`).
      def xpath(*args)
        Search.xpath(self, Search.paths(args).join(" | "), Search.bindings(self, Search.namespace_arg(args)))
      end

      def at_xpath(*args)
        xpath(*args).first
      end

      def css(*rules)
        ns = Search.root_namespaces(self)
        Search.xpath(self, CSS.translate(rules.join(", "), css_contexts, ns.key?("xmlns")), Search.encode(ns))
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

      def to_xml
        @ref.__serialize(SaveOptions::DEFAULT_XML)
        NokogiriExt.sp_noko_out
      end

      # The gem's: XML in an XML document, HTML in an HTML one.
      def to_s
        document.xml? ? to_xml : to_html
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

      def version
        v = @ref.__version
        v == "" ? nil : v
      end

      def name
        "document"
      end

      def xml?
        node_type == DOCUMENT_NODE
      end

      def html?
        node_type == HTML_DOCUMENT_NODE
      end

      # The errors the parse reported, in order (a recovered document keeps
      # them; a strict parse raises the last).
      def errors
        Document.errors_of(@ref)
      end

      def remove_namespaces!
        @ref.__remove_namespaces
        self
      end

      def self.errors_of(ref)
        out = []
        i = 0
        n = ref.__error_count
        while i < n
          out << SyntaxError.build(ref.__error_message(i), ref.__error_level(i), ref.__error_line(i), ref.__error_column(i))
          i += 1
        end
        out
      end

      # The gem's XML::Document.parse(string, url, encoding, options): an
      # empty string is an empty document; a malformed one is recovered
      # (its errors kept) unless the options are strict, when the last
      # error is raised.
      def self.parse(xml, url = nil, encoding = nil, options = ParseOptions::DEFAULT_XML)
        config = ParseOptions.new(options)
        yield config if block_given?
        s = xml.to_s
        if s.empty?
          raise SyntaxError.build("Empty document", 0, 0, 0) if config.strict?
          return Document.new(NokoNodeRef.new.__new_xml_document)
        end
        ref = NokoNodeRef.new.__parse_xml(s, encoding.to_s, config.to_i)
        unless ref.__present?
          errs = Document.errors_of(ref)
          raise SyntaxError.build("Could not parse document", 0, 0, 0) if errs.empty?
          raise errs.last
        end
        Document.new(ref)
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
        return NodeSet.new([]) if @nodes.empty?
        ns = Search.root_namespaces(@nodes.first)
        xp = CSS.translate(rules.join(", "), [".//", "self::"], ns.key?("xmlns"))
        each_match(xp, Search.encode(ns))
      end

      def xpath(*args)
        return NodeSet.new([]) if @nodes.empty?
        each_match(Search.paths(args).join(" | "), Search.bindings(@nodes.first, Search.namespace_arg(args)))
      end

      def each_match(expr, bindings)
        out = []
        @nodes.each do |n|
          Search.xpath(n, expr, bindings).to_a.each { |m| out << m unless out.any? { |o| o == m } }
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
      def self.xpath(node, expr, bindings)
        n = node.__ref.__xpath(expr, bindings)
        if n == -1
          raise XPath::SyntaxError.build("#{NokogiriExt.sp_noko_xpath_error}: #{expr}", 2, 0, 0)
        end
        out = []
        i = 0
        while i < n
          r = Node.wrap(node.__ref.__xpath_result(i))
          out << r unless r.nil?
          i += 1
        end
        NodeSet.new(out)
      end

      # xpath's arguments: the paths, then optionally a Hash of namespace
      # bindings.
      def self.paths(args)
        out = []
        args.each { |a| out << a.to_s unless a.is_a?(Hash) }
        out
      end

      def self.namespace_arg(args)
        ns = nil
        args.each { |a| ns = a if a.is_a?(Hash) }
        ns
      end

      # The gem's default bindings: the root's namespaces.
      def self.root_namespaces(node)
        root = node.document.root
        root.nil? ? {} : root.namespaces
      end

      # Bindings as the native side registers them ("prefix\thref" lines),
      # each key stripped of "xmlns:" as the gem's register_namespaces does.
      def self.bindings(node, ns)
        encode(ns.nil? ? root_namespaces(node) : ns)
      end

      def self.encode(ns)
        out = +""
        ns.each do |k, v|
          key = k.to_s
          colon = key.rindex(":")
          key = key[(colon + 1)..] unless colon.nil?
          out << key << "\t" << v.to_s << "\n"
        end
        out
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
    class SyntaxError < Nokogiri::SyntaxError
    end

    def self.xpath_for(selector)
      translate(selector, ["//"], false).split(" | ")
    end

    # The whole selector list as one XPath union: libxml2 sorts a union into
    # document order, which is what the gem answers for a comma list. In a
    # document with a default namespace (`default_ns`), an element name
    # with no namespace of its own is in it, as the gem writes: `xmlns:`.
    def self.translate(selector, contexts, default_ns)
      parts = []
      split_list(selector).each do |sel|
        body = one(sel.strip, default_ns)
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
    def self.one(sel, default_ns)
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
            out << compound(cur, default_ns)
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
      out << compound(cur, default_ns) unless cur.empty?
      out
    end

    # tag or * (or ns|tag) followed by #id, .class and [attr…] parts.
    def self.compound(c, default_ns)
      i = 0
      tag = +""
      while i < c.length && c[i] != "#" && c[i] != "." && c[i] != "["
        tag << c[i]
        i += 1
      end
      tag = +"*" if tag.empty?
      bar = tag.index("|")
      prefix = bar.nil? ? nil : tag[0...bar]
      tag = tag[(bar + 1)..] unless bar.nil?
      unless (tag == "*" || tag.match?(/\A[A-Za-z][A-Za-z0-9_-]*\z/)) &&
             (prefix.nil? || prefix.empty? || prefix.match?(/\A[A-Za-z_][A-Za-z0-9_.-]*\z/))
        raise SyntaxError, "nokogiri (spinel): unsupported CSS selector: #{c}"
      end
      if !prefix.nil?
        tag = prefix + ":" + tag unless prefix.empty?
      elsif default_ns && tag != "*"
        tag = "xmlns:" + tag
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
      m = body.match(/\A\s*([A-Za-z_:][A-Za-z0-9_:.-]*(?:\|[A-Za-z_][A-Za-z0-9_.-]*)?)\s*(?:([~|^$*]?=)\s*(.+?))?\s*\z/)
      raise SyntaxError, "nokogiri (spinel): unsupported attribute selector: [#{body}]" if m.nil?
      name = m[1].to_s.sub("|", ":")
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
