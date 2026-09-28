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
  ffi_func :sp_noko_gumbo_status,   [], :str
  ffi_func :sp_noko_parse_error_count,   [], :int
  ffi_func :sp_noko_parse_error_level,   [:int], :int
  ffi_func :sp_noko_parse_error_line,    [:int], :int
  ffi_func :sp_noko_parse_error_column,  [:int], :int
  ffi_func :sp_noko_parse_error_message, [:int], :str
end

# The native half of a node: one xmlNode plus the owner of its document
# (sp_nokogiri.c). Its own top-level name, for the reason spinel-ruby-vips
# gives: a native class is keyed by its last segment, so a native
# `Nokogiri::XML::Node` would merge with any other `Node` in the program.
module NokogiriNodePackage
  # A C string the native side answers is libxml2's (or the package's own)
  # storage, not a Spinel string, so it is declared `:cstring`: Spinel
  # copies it onto its string heap. (`:string` would hand Spinel the
  # pointer as is, and its string functions read the byte before a string
  # of their own for a header.)
  native_struct "NokoNodeRef", "sp_NokoNode", "sp_NokoNode_fin"
  native_new [], "sp_NokoNode_new"

  native_method :__present?,         [], :bool,                     "sp_NokoNode_present_p"
  native_method :__same?,            [:any], :bool,                 "sp_NokoNode_same_p"
  native_method :__parse_html,       [:string, :string, :int], :self, "sp_NokoNode_parse_html"
  native_method :__parse_xml,        [:string, :string, :int], :self, "sp_NokoNode_parse_xml"
  native_method :__new_xml_document, [], :self,                     "sp_NokoNode_new_xml_document"
  native_method :__parse_html5,      [:string, :int, :int, :int, :bool], :self, "sp_NokoNode_parse_html5"
  native_method :__new_html5_document, [], :self,                   "sp_NokoNode_new_html5_document"
  native_method :__new_html_document, [:bool], :self,               "sp_NokoNode_new_html_document"
  native_method :__set_encoding,     [:string], :void,              "sp_NokoNode_set_encoding"
  native_method :__html5?,           [], :bool,                     "sp_NokoNode_html5_p"
  native_method :__quirks_mode,      [], :int,                      "sp_NokoNode_quirks_mode"
  native_method :__html5_fragment,   [:string, :string, :int, :bool, :string, :bool, :int, :int, :int, :bool], :int, "sp_NokoNode_html5_fragment"
  native_method :__html5_serialize,  [:bool], :int,                 "sp_NokoNode_html5_serialize"
  native_method :__error_count,      [], :int,                      "sp_NokoNode_error_count"
  native_method :__error_level,      [:int], :int,                  "sp_NokoNode_error_level"
  native_method :__error_line,       [:int], :int,                  "sp_NokoNode_error_line"
  native_method :__error_column,     [:int], :int,                  "sp_NokoNode_error_column"
  native_method :__error_message,    [:int], :cstring,               "sp_NokoNode_error_message"
  native_method :__type,             [], :int,                      "sp_NokoNode_type"
  native_method :__name,             [], :cstring,                   "sp_NokoNode_name"
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
  native_method :__attr_name,        [:int], :cstring,               "sp_NokoNode_attr_name"
  native_method :__set_name,         [:string], :void,              "sp_NokoNode_set_name"
  native_method :__set_attr,         [:string, :string], :void,     "sp_NokoNode_set_attr"
  native_method :__remove_attr,      [:string], :void,              "sp_NokoNode_remove_attr"
  native_method :__attr_node,        [:int], :self,                 "sp_NokoNode_attr_node"
  native_method :__attr_named,       [:string], :self,              "sp_NokoNode_attr_named"
  native_method :__set_attr_value,   [:string], :void,              "sp_NokoNode_set_attr_value"
  native_method :__encode_special_chars, [:string], :int,           "sp_NokoNode_encode_special_chars"
  native_method :__set_content,      [:string], :void,              "sp_NokoNode_set_content"
  native_method :__create_element,   [:string], :self,              "sp_NokoNode_create_element"
  native_method :__create_text,      [:string], :self,              "sp_NokoNode_create_text"
  native_method :__create_cdata,     [:string], :self,              "sp_NokoNode_create_cdata"
  native_method :__create_fragment,  [], :self,                     "sp_NokoNode_create_fragment"
  native_method :__unlink,           [], :void,                     "sp_NokoNode_unlink"
  native_method :__add_previous_sibling, [:any], :self,             "sp_NokoNode_add_previous_sibling"
  native_method :__add_next_sibling, [:any], :self,                 "sp_NokoNode_add_next_sibling"
  native_method :__add_child,        [:any], :self,                 "sp_NokoNode_add_child"
  native_method :__replace,          [:any], :self,                 "sp_NokoNode_replace"
  native_method :__dup,              [:int], :self,                 "sp_NokoNode_dup"
  native_method :__in_context,       [:string, :int], :int,         "sp_NokoNode_in_context"
  native_method :__in_context_result, [:int], :self,                "sp_NokoNode_in_context_result"
  native_method :__xpath,            [:string, :string], :int,      "sp_NokoNode_xpath"
  native_method :__xpath_result,     [:int], :self,                 "sp_NokoNode_xpath_result"
  native_method :__serialize,        [:int], :int,                  "sp_NokoNode_serialize"
  native_method :__encoding,         [], :cstring,                   "sp_NokoNode_encoding"
  native_method :__version,          [], :cstring,                   "sp_NokoNode_version"
  native_method :__namespace,        [], :int,                      "sp_NokoNode_namespace"
  native_method :__namespace_scopes, [], :int,                      "sp_NokoNode_namespace_scopes"
  native_method :__namespace_definitions, [], :int,                 "sp_NokoNode_namespace_definitions"
  native_method :__remove_namespaces, [], :void,                    "sp_NokoNode_remove_namespaces"
  native_method :__path,             [], :int,                      "sp_NokoNode_path"
  native_method :__line,             [], :int,                      "sp_NokoNode_line"
  native_method :__blank?,           [], :bool,                     "sp_NokoNode_blank_p"
end

module Nokogiri
  # The gem version this package answers as (its snapshots are 1.19.4's).
  VERSION = "1.19.4"

  class SyntaxError < StandardError
  end

  # HTML5 is gumbo's, as in the gem on CRuby.
  def self.uses_gumbo?
    true
  end

  def self.jruby?
    nil
  end

  # The gem's VersionInfo, for the one question libraries ask of it.
  class VersionInfo
    def self.instance
      @instance ||= new
    end

    def libxml2?
      true
    end
  end

  # The gem's Nokogiri::XML(string, url, encoding, options) — an XML
  # document, the parse options adjustable in a block.
  def self.XML(xml, url = nil, encoding = nil, options = XML::ParseOptions::DEFAULT_XML, &block)
    XML::Document.parse(xml, url, encoding, options, &block)
  end

  module XML
    def self.fragment(tags)
      DocumentFragment.parse(tags)
    end
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
    DOCUMENT_FRAG_NODE = 11
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

    # The gem's DocumentFragment: nodes with no parent of their own, held by
    # a fragment node in a document. Without a context the markup is
    # parsed on its own (inside a <root>); with one, in that node's
    # context (Node#parse).
    class DocumentFragment
      def initialize(document, tags = nil, context = nil, options = ParseOptions::DEFAULT_XML)
        @doc = document
        @frag = Node.new(document.__ref.__create_fragment)
        @errors = []
        fill(tags, context, options) unless tags.nil?
      end

      def fill(tags, context, options)
        if context.nil?
          wrapper = Document.parse("<root>#{tags}</root>", nil, nil, options)
          @errors = wrapper.errors
          nodes = wrapper.xpath("/root/node()")
        else
          nodes = context.parse(tags, options)
        end
        nodes.each { |c| @frag.__ref.__add_child(c.__ref) }
        nil
      end

      def self.parse(tags)
        DocumentFragment.new(Document.new(NokoNodeRef.new.__new_xml_document), tags)
      end

      def document
        @doc
      end

      def errors
        @errors
      end

      def children
        @frag.children
      end

      def fragment?
        true
      end

      def add_child(node_or_tags)
        @frag.add_child(node_or_tags)
      end

      def css(*rules)
        children.css(*rules)
      end

      def at_css(*rules)
        children.css(*rules).first
      end

      # The gem's: XPath from the fragment node (so "./body" is a child
      # of the fragment); CSS over the children.
      def xpath(*paths)
        @frag.xpath(*paths)
      end

      def at_xpath(*paths)
        xpath(*paths).first
      end

      def search(*rules)
        r = rules.join(", ")
        Search.looks_like_xpath?(r) ? xpath(r) : children.css(r)
      end

      def xml?
        false
      end

      def html?
        false
      end

      # The gem's: a new fragment of the same class, holding copies of
      # these children.
      def dup
        copy = self.class.new(@doc)
        children.each { |c| copy.add_child(c.dup(1)) }
        copy
      end

      def text
        children.text
      end

      def inner_html
        children.to_html
      end

      def to_html(encoding: nil)
        Node.check_encoding(encoding)
        children.to_html
      end

      def to_xml(encoding: nil)
        Node.check_encoding(encoding)
        children.to_xml
      end

      def to_s
        children.to_s
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
        parts << @text.to_s.chomp
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

      # The node types, where the gem keeps them (Loofah reads
      # Nokogiri::XML::Node::ELEMENT_NODE).
      ELEMENT_NODE = XML::ELEMENT_NODE
      ATTRIBUTE_NODE = XML::ATTRIBUTE_NODE
      TEXT_NODE = XML::TEXT_NODE
      CDATA_SECTION_NODE = XML::CDATA_SECTION_NODE
      PI_NODE = XML::PI_NODE
      COMMENT_NODE = XML::COMMENT_NODE
      DOCUMENT_NODE = XML::DOCUMENT_NODE
      DOCUMENT_FRAG_NODE = XML::DOCUMENT_FRAG_NODE
      HTML_DOCUMENT_NODE = XML::HTML_DOCUMENT_NODE
      DTD_NODE = XML::DTD_NODE

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

      def type
        node_type
      end

      def xml?
        node_type == DOCUMENT_NODE
      end

      def html?
        node_type == HTML_DOCUMENT_NODE
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

      def node_name
        name
      end

      # The document, as the class it was made as: an HTML5, HTML4 or XML
      # document.
      def document
        Document.wrap(@ref.__document)
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

      def elements
        element_children
      end

      def first_element_child
        c = child
        c = c.next_sibling while c && !c.element?
        c
      end

      def last_element_child
        c = Node.wrap(@ref.__last_child)
        c = c.previous_sibling while c && !c.element?
        c
      end

      def next_element
        c = next_sibling
        c = c.next_sibling while c && !c.element?
        c
      end

      def previous_element
        c = previous_sibling
        c = c.previous_sibling while c && !c.element?
        c
      end

      # The gem's: every ancestor up to the document, nearest first; with a
      # selector, the ones it matches.
      def ancestors(selector = nil)
        parents = []
        p = parent
        while p
          parents << p
          p = p.parent
        end
        return NodeSet.new(parents) if selector.nil? || parents.empty?
        found = parents.last.search(selector)
        NodeSet.new(parents.select { |a| found.include?(a) })
      end

      # The gem's: children first, depth first, then self.
      def traverse(&block)
        children.each { |c| c.traverse(&block) }
        yield self
        self
      end

      def matches?(selector)
        top = ancestors.last
        top.nil? ? false : top.search(selector).include?(self)
      end

      def blank?
        @ref.__blank?
      end

      def path
        @ref.__path
        NokogiriExt.sp_noko_out
      end

      def line
        @ref.__line
      end

      def <<(node)
        add_child(node)
        self
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

      # The attribute node itself (XML::Attr), or nil.
      def attribute(key)
        r = @ref.__attr_named(key.to_s)
        r.__present? ? Attr.new(r) : nil
      end

      # The attribute nodes, in document order: live, so editing or
      # removing one edits this element (Loofah's scrubbers do both).
      def attribute_nodes
        out = []
        i = 0
        n = @ref.__attr_count
        while i < n
          out << Attr.new(@ref.__attr_node(i))
          i += 1
        end
        out
      end

      # name => Attr, in document order (a later attribute with the same
      # local name, xlink:href after href, replaces the earlier, as in the
      # gem).
      def attributes
        h = {}
        attribute_nodes.each { |a| h[a.name] = a }
        h
      end

      def keys
        attributes.keys
      end

      def values
        attributes.values.map { |a| a.value }
      end

      def value?(value)
        values.include?(value)
      end

      # The gem's: [name, value] per attribute, in document order.
      def each
        attributes.each { |k, a| yield [k, a.value] }
        self
      end

      def delete(key)
        remove_attribute(key)
      end

      # ---- class keywords (the gem's kwattr_*) ---------------------------

      def classes
        Node.keywords(self["class"].to_s)
      end

      def add_class(names)
        current = classes
        Node.keywords(names).each { |k| current << k unless current.include?(k) }
        self["class"] = current.join(" ")
        self
      end

      def append_class(names)
        self["class"] = (classes + Node.keywords(names)).join(" ")
        self
      end

      def remove_class(names = nil)
        if names.nil?
          remove_attribute("class")
          return self
        end
        drop = Node.keywords(names)
        left = classes.reject { |k| drop.include?(k) }
        if left.empty?
          remove_attribute("class")
        else
          self["class"] = left.join(" ")
        end
        self
      end

      # A String's whitespace-separated words, or an Array's strings.
      def self.keywords(names)
        return names.map { |n| n.to_s } if names.is_a?(Array)
        names.to_s.split(/\s+/).reject { |w| w.empty? }
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

      # The gem's: xmlEncodeSpecialChars, in this node's document.
      def encode_special_chars(s)
        @ref.__encode_special_chars(s.to_s)
        NokogiriExt.sp_noko_out
      end

      # The gem's: the special characters are encoded, so "<" stays text.
      def content=(s)
        @ref.__set_content(s.to_s)
        s
      end

      # ---- editing -------------------------------------------------------
      #
      # Each of these takes a node, a NodeSet, or markup: a String is
      # parsed in the context of where it is going (Node#coerce), so
      # `tr.add_child("<td>…")` makes a cell. A node from another document
      # is copied in, and the handle passed now holds the copy, as in the
      # gem.

      # The gem's: nodes to add, from a node, a NodeSet, a fragment or
      # markup.
      def coerce(data)
        return data if data.is_a?(NodeSet)
        return data.children if data.is_a?(DocumentFragment)
        return fragment(data).children if data.is_a?(String)
        return data if data.is_a?(Node) && !data.is_a?(Document)
        raise ArgumentError, "Requires a Node, NodeSet or String argument, and cannot accept a #{data.class}."
      end

      def add_child(node_or_tags)
        nodes = coerce(node_or_tags)
        if nodes.is_a?(NodeSet)
          nodes.each { |n| @ref.__add_child(n.__ref) }
        else
          @ref.__add_child(nodes.__ref)
        end
        nodes
      end

      def <<(node_or_tags)
        add_child(node_or_tags)
        self
      end

      # The gem's: this node moves under the new parent, as its last child.
      def parent=(parent_node)
        parent_node.add_child(self)
      end

      def add_previous_sibling(node_or_tags)
        check_root_sibling(node_or_tags)
        add_sibling(false, node_or_tags)
      end

      def add_next_sibling(node_or_tags)
        check_root_sibling(node_or_tags)
        add_sibling(true, node_or_tags)
      end

      def before(node_or_tags)
        add_previous_sibling(node_or_tags)
        self
      end

      def after(node_or_tags)
        add_next_sibling(node_or_tags)
        self
      end

      # The gem's: prepend before the first child, or add the only one.
      def prepend_child(node_or_tags)
        first = child
        return add_child(node_or_tags) if first.nil?
        if document? && !(node_or_tags.is_a?(Node) && (node_or_tags.comment? || node_or_tags.processing_instruction?))
          raise "Document already has a root node"
        end
        first.add_sibling(false, node_or_tags)
      end

      # The gem's replace: a NodeSet goes in node by node before this one,
      # a node takes this one's place; either way this one is unlinked. A
      # text node is first swapped for a placeholder element, as the gem
      # does.
      def replace(node_or_tags)
        raise "Cannot replace a node with no parent" if parent.nil?
        if text?
          dummy = document.create_element("dummy")
          @ref.__add_previous_sibling(dummy.__ref)
          unlink
          return dummy.replace(node_or_tags)
        end
        nodes = parent.coerce(node_or_tags)
        if nodes.is_a?(NodeSet)
          nodes.each { |n| add_previous_sibling(n) }
          unlink
        else
          @ref.__replace(nodes.__ref)
        end
        nodes
      end

      def swap(node_or_tags)
        replace(node_or_tags)
        self
      end

      def children=(node_or_tags)
        nodes = coerce(node_or_tags)
        children.unlink
        if nodes.is_a?(NodeSet)
          nodes.each { |n| @ref.__add_child(n.__ref) }
        else
          @ref.__add_child(nodes.__ref)
        end
      end

      def inner_html=(node_or_tags)
        self.children = node_or_tags
      end

      # The gem's wrap: markup (parsed where this node is) or a copy of a
      # node becomes this node's new parent, in this node's place.
      def wrap(node_or_tags)
        if node_or_tags.is_a?(String)
          context = parent.nil? ? document : parent
          new_parent = context.coerce(node_or_tags).first
          raise "Failed to parse '#{node_or_tags}' in the context of a '#{context.name}' element" if new_parent.nil?
        else
          new_parent = node_or_tags.dup
        end
        if parent.nil?
          new_parent.unlink
        else
          add_next_sibling(new_parent)
        end
        new_parent.add_child(self)
        self
      end

      # A copy in this document: with its children (level 1) or not (0).
      def dup(level = 1)
        Node.wrap(@ref.__dup(level))
      end

      def unlink
        @ref.__unlink
        self
      end

      def remove
        unlink
      end

      # The gem's Node#parse: markup parsed in this node's context
      # (xmlParseInNodeContext), answering the new top-level nodes, not
      # yet in the tree. A parse with errors raises unless the options
      # recover, and one that recovers nothing falls back to a
      # context-free fragment.
      def parse(string, options = nil)
        if !element? && !document? && (parent.nil? || parent.fragment?)
          return document.parse(string, options)
        end
        opts = options.nil? ? (document.html? ? ParseOptions::DEFAULT_HTML : ParseOptions::DEFAULT_XML) : options
        return NodeSet.new([]) if string.empty?
        before = @ref.__error_count
        n = @ref.__in_context(string, opts)
        out = []
        i = 0
        while i < n
          r = Node.wrap(@ref.__in_context_result(i))
          out << r unless r.nil?
          i += 1
        end
        set = NodeSet.new(out)
        if @ref.__error_count > before
          raise Document.errors_of(@ref)[before] if opts & ParseOptions::RECOVER == 0
          if set.empty?
            set = document.html? ? HTML4::DocumentFragment.parse(string).children : DocumentFragment.parse(string).children
          end
        end
        set
      end

      # The gem's: a fragment of markup parsed in this node's context.
      def fragment(tags)
        return HTML5::DocumentFragment.new(document, tags, self) if @ref.__html5?
        return HTML4::DocumentFragment.new(document, tags, self) if document.html?
        DocumentFragment.new(document, tags, self)
      end

      def fragment?
        node_type == DOCUMENT_FRAG_NODE
      end

      def add_sibling(nxt, node_or_tags)
        raise "Cannot add sibling to a node with no parent" if parent.nil?
        nodes = parent.coerce(node_or_tags)
        if nodes.is_a?(NodeSet)
          pivot = self
          if text?
            pivot = document.create_element("dummy")
            nxt ? @ref.__add_next_sibling(pivot.__ref) : @ref.__add_previous_sibling(pivot.__ref)
          end
          list = nxt ? nodes.to_a.reverse : nodes.to_a
          list.each do |n|
            nxt ? pivot.__ref.__add_next_sibling(n.__ref) : pivot.__ref.__add_previous_sibling(n.__ref)
          end
          pivot.unlink if text?
        else
          nxt ? @ref.__add_next_sibling(nodes.__ref) : @ref.__add_previous_sibling(nodes.__ref)
        end
        nodes
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
        Search.xpath(self, CSS.translate(rules.join(", "), css_contexts, CSS.mode(self, ns)), Search.encode(ns))
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

      # In an HTML5 document, the HTML standard's serialization (the gem's
      # html_standard_serialize); otherwise libxml2's HTML writer.
      def to_html(encoding: nil)
        Node.check_encoding(encoding)
        if @ref.__html5?
          @ref.__html5_serialize(false)
        else
          @ref.__serialize(SaveOptions::DEFAULT_HTML)
        end
        NokogiriExt.sp_noko_out
      end

      def to_xml(encoding: nil)
        Node.check_encoding(encoding)
        @ref.__serialize(SaveOptions::DEFAULT_XML)
        NokogiriExt.sp_noko_out
      end

      # The one encoding a serialization is written in here: UTF-8, the
      # String's own (see "Subset" in the README). Asking for it by name,
      # as rails-html-sanitizer does, is the same serialization.
      def self.check_encoding(encoding)
        return nil if encoding.nil? || encoding.to_s.upcase == "UTF-8"
        raise NotImplementedError, "nokogiri (spinel): serializing as #{encoding} is not supported; only UTF-8"
      end

      # The gem's: XML in an XML document, HTML in an HTML one.
      def to_s
        document.xml? ? to_xml : to_html
      end

      def inner_html
        children.to_a.map { |c| c.to_html }.join
      end

      private

      # The gem's: a document takes one root element.
      def check_root_sibling(node_or_tags)
        p = parent
        return nil if p.nil? || !p.document?
        return nil if node_or_tags.is_a?(Node) && (node_or_tags.comment? || node_or_tags.processing_instruction?)
        raise ArgumentError, "A document may not have multiple root nodes."
      end
    end

    class Document < Node
      # The gem's Document.new: an empty version-1.0 document. A ref is the
      # document a parse made (parse answers the class it was called on,
      # so a subclass parses as itself).
      def initialize(ref = nil)
        @ref = ref.nil? ? NokoNodeRef.new.__new_xml_document : ref
      end

      def self.wrap(ref)
        return HTML5::Document.new(ref) if ref.__html5?
        return HTML4::Document.new(ref) if ref.__type == HTML_DOCUMENT_NODE
        Document.new(ref)
      end

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

      # The gem's: a fragment parsed in the root's context (or none).
      def fragment(tags = nil)
        return HTML4::DocumentFragment.new(self, tags, root) if html?
        DocumentFragment.new(self, tags, root)
      end

      def create_text_node(text)
        Node.wrap(@ref.__create_text(text.to_s))
      end

      def create_cdata(text)
        Node.wrap(@ref.__create_cdata(text.to_s))
      end

      def encoding
        e = @ref.__encoding
        e == "" ? nil : e
      end

      def encoding=(e)
        @ref.__set_encoding(e.to_s)
      end

      def version
        v = @ref.__version
        v == "" ? nil : v
      end

      def name
        "document"
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
          return new
        end
        ref = NokoNodeRef.new.__parse_xml(s, encoding.to_s, config.to_i)
        unless ref.__present?
          errs = Document.errors_of(ref)
          raise SyntaxError.build("Could not parse document", 0, 0, 0) if errs.empty?
          raise errs.last
        end
        new(ref)
      end
    end

    # An attribute, as the node libxml2 keeps it: live, so value= and
    # remove edit the element it is on. Node supplies name, namespace,
    # parent and unlink/remove.
    class Attr < Node
      def value
        content
      end

      def value=(v)
        @ref.__set_attr_value(v.to_s)
        v
      end

      def content=(v)
        self.value = v
      end

      def to_s
        content
      end
    end

    # The gem's Text.new(string, document): a text node made in the
    # document (any node of it will do), not yet in the tree.
    class Text < Node
      def initialize(string, document)
        @ref = document.__ref.__create_text(string.to_s)
      end
    end

    # The gem's NodeSet: an ordered set of nodes that is Enumerable (so
    # select, reject, sort_by, … answer Arrays, as the gem's do), with set
    # operations, bulk edits, and searches over every member.
    class NodeSet
      def initialize(nodes)
        @nodes = nodes
      end

      def to_a
        @nodes
      end

      def to_ary
        @nodes
      end

      # ---- Enumerable ----------------------------------------------------

      def each(&block)
        @nodes.each(&block)
        self
      end

      def each_with_index(&block)
        @nodes.each_with_index(&block)
        self
      end

      def each_with_object(memo)
        @nodes.each { |n| yield n, memo }
        memo
      end

      def each_slice(n)
        i = 0
        while i < @nodes.length
          yield @nodes[i, n]
          i += n
        end
        nil
      end

      def map(&block)
        @nodes.map(&block)
      end

      def collect(&block)
        @nodes.map(&block)
      end

      def flat_map(&block)
        @nodes.flat_map(&block)
      end

      def filter_map(&block)
        @nodes.filter_map(&block)
      end

      def select(&block)
        @nodes.select(&block)
      end

      def find_all(&block)
        @nodes.select(&block)
      end

      def reject(&block)
        @nodes.reject(&block)
      end

      def partition(&block)
        @nodes.partition(&block)
      end

      def group_by(&block)
        @nodes.group_by(&block)
      end

      def sort_by(&block)
        @nodes.sort_by(&block)
      end

      def min_by(&block)
        @nodes.min_by(&block)
      end

      def max_by(&block)
        @nodes.max_by(&block)
      end

      def inject(init)
        acc = init
        @nodes.each { |n| acc = yield(acc, n) }
        acc
      end

      def reduce(init)
        acc = init
        @nodes.each { |n| acc = yield(acc, n) }
        acc
      end

      def find(&block)
        @nodes.find(&block)
      end

      def detect(&block)
        @nodes.find(&block)
      end

      def find_index(&block)
        @nodes.find_index(&block)
      end

      # The gem's: the index of a node (by ==), or of the first a block
      # accepts; nil if none.
      # The gem's index(node). Its block form (index { |n| … }) is
      # find_index here until matz/spinel#5097: a method that yields, called
      # both ways, does not link.
      def index(node)
        i = 0
        while i < @nodes.length
          return i if @nodes[i] == node
          i += 1
        end
        nil
      end

      def include?(node)
        NodeSet.member?(@nodes, node)
      end

      # Membership by the node's == (the same xmlNode), for an Array of
      # nodes.
      def self.member?(nodes, node)
        i = 0
        while i < nodes.length
          return true if nodes[i] == node
          i += 1
        end
        false
      end

      def any?(&block)
        return !@nodes.empty? unless block_given?
        @nodes.any?(&block)
      end

      def all?(&block)
        @nodes.all?(&block)
      end

      def none?(&block)
        @nodes.none?(&block)
      end

      def count(&block)
        return @nodes.length unless block_given?
        @nodes.count(&block)
      end

      def take(n)
        @nodes.take(n)
      end

      def drop(n)
        @nodes.drop(n)
      end

      def length
        @nodes.length
      end

      def size
        @nodes.length
      end

      def empty?
        @nodes.empty?
      end

      # The gem's first(n): an Array of the first n.
      def first(n = nil)
        return @nodes.first if n.nil?
        @nodes.take(n)
      end

      def last
        @nodes.last
      end

      # The gem's []: a node for an index, a NodeSet for (start, length) or
      # a range.
      def [](i, len = nil)
        # (exclusive when the range leaves out its own end: exclude_end? is
        # not reachable here yet, matz/spinel#5095)
        return range(i.begin, i.end, !i.end.nil? && !i.include?(i.end)) if i.is_a?(Range)
        return NodeSet.new(@nodes[i, len] || []) unless len.nil?
        @nodes[i]
      end

      # nodes[a..b] / nodes[a...b], an endless or beginless range too.
      def range(first, last, exclusive)
        from = first.nil? ? 0 : first
        to = last.nil? ? -1 : last
        from += @nodes.length if from < 0
        to += @nodes.length if to < 0
        to -= 1 if exclusive && !last.nil?
        out = []
        k = from
        while k <= to && k < @nodes.length
          out << @nodes[k] if k >= 0
          k += 1
        end
        NodeSet.new(out)
      end

      def slice(i, len = nil)
        self[i, len]
      end

      def reverse
        NodeSet.new(@nodes.reverse)
      end

      # ---- as a set --------------------------------------------------------

      def |(other)
        out = @nodes.dup
        other.to_a.each { |n| out << n unless NodeSet.member?(out, n) }
        NodeSet.new(out)
      end

      def +(other)
        self | other
      end

      def &(other)
        NodeSet.new(@nodes.select { |n| other.include?(n) })
      end

      def -(other)
        NodeSet.new(@nodes.reject { |n| other.include?(n) })
      end

      def ==(other)
        return false unless other.is_a?(NodeSet) && other.length == length
        i = 0
        while i < length
          return false unless @nodes[i] == other[i]
          i += 1
        end
        true
      end

      def push(node)
        @nodes << node unless include?(node)
        self
      end

      def <<(node)
        push(node)
      end

      def delete(node)
        i = index(node)
        return nil if i.nil?
        @nodes.delete_at(i)
      end

      def pop
        @nodes.pop
      end

      def shift
        @nodes.shift
      end

      def children
        out = []
        @nodes.each { |n| n.children.each { |c| out << c } }
        NodeSet.new(out)
      end

      # ---- searching -----------------------------------------------------

      # The gem's NodeSet#css: each node searched with ".//" AND "self::",
      # so a node of the set that itself matches is found.
      def css(*rules)
        return NodeSet.new([]) if @nodes.empty?
        ns = Search.root_namespaces(@nodes.first)
        xp = CSS.translate(rules.join(", "), [".//", "self::"], CSS.mode(@nodes.first, ns))
        each_match(xp, Search.encode(ns))
      end

      def xpath(*args)
        return NodeSet.new([]) if @nodes.empty?
        each_match(Search.paths(args).join(" | "), Search.bindings(@nodes.first, Search.namespace_arg(args)))
      end

      def each_match(expr, bindings)
        out = []
        @nodes.each do |n|
          Search.xpath(n, expr, bindings).to_a.each { |m| out << m unless NodeSet.member?(out, m) }
        end
        NodeSet.new(out)
      end

      def at_css(*rules)
        css(*rules).first
      end

      def at_xpath(*args)
        xpath(*args).first
      end

      def search(*rules)
        r = rules.join(", ")
        Search.looks_like_xpath?(r) ? xpath(r) : css(r)
      end

      def at(*rules)
        search(*rules).first
      end

      # The gem's filter(selector): the members the selector matches.
      def filter(selector)
        @nodes.select { |n| n.matches?(selector) }
      end

      # ---- attributes and classes, over every member ---------------------

      # The gem's NodeSet#attribute(name): the first node's.
      def attribute(key)
        n = @nodes.first
        n.nil? ? nil : n.attribute(key)
      end

      # attr(name) reads the first node's; attr(name, value) sets it on
      # every node.
      def attr(key, value = nil)
        return attribute(key) if value.nil?
        set(key, value)
      end

      def set(key, value)
        @nodes.each { |n| n[key] = value }
        self
      end

      def remove_attr(key)
        @nodes.each { |n| n.remove_attribute(key) }
        self
      end

      def remove_attribute(key)
        remove_attr(key)
      end

      def add_class(names)
        @nodes.each { |n| n.add_class(names) }
        self
      end

      def append_class(names)
        @nodes.each { |n| n.append_class(names) }
        self
      end

      def remove_class(names = nil)
        @nodes.each { |n| n.remove_class(names) }
        self
      end

      # ---- content and editing -------------------------------------------

      def text
        @nodes.map { |n| n.text }.join
      end

      def inner_text
        text
      end

      def to_html
        @nodes.map { |n| n.to_html }.join
      end

      def to_xml
        @nodes.map { |n| n.to_xml }.join
      end

      def to_s
        @nodes.map { |n| n.to_s }.join
      end

      def inner_html
        @nodes.map { |n| n.inner_html }.join
      end

      def before(node)
        @nodes.first.before(node)
      end

      def after(node)
        @nodes.last.after(node)
      end

      def remove
        @nodes.each { |n| n.unlink }
        self
      end

      def unlink
        remove
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
  # (Nokogiri::CSS::XPathVisitor), so a query finds what the gem's finds:
  # type, universal and `ns|name` selectors; `#id`, `.class` and attribute
  # selectors (`[a]`, `=`, `!=`, `~=`, `|=`, `^=`, `$=`, `*=`); the
  # descendant, child (`>`), adjacent (`+`) and general sibling (`~`)
  # combinators, leading ones too (`> p`); comma lists; and the
  # pseudo-classes, with the gem's own XPath for each. A pseudo-class the
  # gem hands to a custom handler (`:even`, `:checked`, …) becomes the same
  # `nokogiri:` call, which libxml2 rejects as the gem's does without a
  # handler. Where the gem's parse would silently drop part of a selector
  # (`:not(p.x)`, `:has(a, b)`), this raises instead.
  module CSS
    class SyntaxError < Nokogiri::SyntaxError
    end

    def self.xpath_for(selector)
      translate(selector, ["//"], 0).split(" | ")
    end

    # How element names are written: 0 as they are, 1 in the document's
    # default namespace (`xmlns:name`), 2 in any namespace (`*:name`, an
    # HTML5 document, where SVG and MathML elements have one).
    def self.mode(node, ns)
      return 2 if node.__ref.__html5?
      ns.key?("xmlns") ? 1 : 0
    end

    # The whole selector list as one XPath union: libxml2 sorts a union into
    # document order, which is what the gem answers for a comma list. In a
    # document with a default namespace (`mode`), an element name
    # with no namespace of its own is in it, as the gem writes: `xmlns:`.
    # A selector that starts with a combinator is relative to the node
    # itself, so it takes no context.
    def self.translate(selector, contexts, mode)
      parts = []
      split_list(selector).each do |sel|
        body = one(sel.strip, mode)
        if body.start_with?("./")
          parts << body
        else
          contexts.each { |ctx| parts << (ctx + body) }
        end
      end
      parts.join(" | ")
    end

    # Splits on commas outside quotes, brackets and parentheses.
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
        elsif ch == "[" || ch == "("
          depth += 1
          cur << ch
        elsif ch == "]" || ch == ")"
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

    # The XPath step a combinator writes before the next compound; a
    # leading one is taken from the node itself (`./`).
    def self.joiner(comb, leading)
      step = if comb == ">"
               "/"
             elsif comb == "+"
               "/following-sibling::*[1]/self::"
             elsif comb == "~"
               "/following-sibling::"
             else
               "//"
             end
      leading ? "." + step : step
    end

    # One complex selector: compounds joined by combinators.
    def self.one(sel, mode)
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
        elsif ch == "[" || ch == "("
          depth += 1
          cur << ch
        elsif ch == "]" || ch == ")"
          depth -= 1
          cur << ch
        elsif depth == 0 && (ch == " " || ch == ">" || ch == "+" || ch == "~")
          unless cur.empty?
            out << compound(cur, mode)
            cur = +""
          end
          if ch != " "
            raise SyntaxError, "nokogiri (spinel): unexpected '#{ch}' in CSS selector: #{sel}" unless comb == "" || comb == " "
            comb = ch
          elsif comb == ""
            comb = " "
          end
        else
          if comb != ""
            out << joiner(comb, out.empty?) unless out.empty? && comb == " "
            comb = ""
          end
          cur << ch
        end
      end
      raise SyntaxError, "nokogiri (spinel): CSS selector ends in a combinator: #{sel}" unless comb == "" || comb == " "
      out << compound(cur, mode) unless cur.empty?
      out
    end

    def self.compound(c, mode)
      parts = compound_parts(c, mode)
      tag = parts[0].empty? ? "*" : parts[0]
      parts[1].empty? ? tag : tag + "[" + parts[1] + "]"
    end

    # A compound's element name as written ("" when there is none) and its
    # conditions, joined as the gem joins them: " and ", except that an
    # of-type pseudo-class opens a bracket of its own ("]["), so its
    # position counts the elements the conditions before it left.
    def self.compound_parts(c, mode)
      i = 0
      tag = +""
      while i < c.length && c[i] != "#" && c[i] != "." && c[i] != "[" && c[i] != ":"
        tag << c[i]
        i += 1
      end
      tag = element_name(tag, mode, c) unless tag.empty?
      preds = +""
      while i < c.length
        ch = c[i]
        pred = +""
        of_type = false
        if ch == "#" || ch == "."
          j = i + 1
          j += 1 while j < c.length && c[j] != "#" && c[j] != "." && c[j] != "[" && c[j] != ":"
          word = c[(i + 1)...j]
          raise SyntaxError, "nokogiri (spinel): unsupported CSS selector: #{c}" if word.empty?
          pred = ch == "#" ? "@id='#{word}'" : css_class("@class", word)
          i = j
        elsif ch == "["
          j = closing(c, i, "[", "]")
          pred = attribute(c[(i + 1)...j])
          i = j + 1
        else
          raise SyntaxError, "nokogiri (spinel): unsupported pseudo-element: #{c}" if c[i + 1] == ":"
          j = i + 1
          j += 1 while j < c.length && c[j].match?(/[A-Za-z0-9_-]/)
          name = c[(i + 1)...j]
          raise SyntaxError, "nokogiri (spinel): unsupported CSS selector: #{c}" if name.empty?
          if j < c.length && c[j] == "("
            k = closing(c, j, "(", ")")
            pred = function(name, c[(j + 1)...k].strip, mode)
            i = k + 1
          else
            pred = pseudo_class(name)
            i = j
          end
          of_type = name.match?(/(nth|first|last|only)-of-type/)
        end
        if preds.empty?
          preds << pred
        else
          preds << (of_type ? "][" : " and ") << pred
        end
      end
      [tag, preds]
    end

    def self.element_name(tag, mode, c)
      bar = tag.index("|")
      prefix = bar.nil? ? nil : tag[0...bar]
      local = bar.nil? ? tag : tag[(bar + 1)..]
      unless (local == "*" || local.match?(/\A[A-Za-z_][A-Za-z0-9_-]*\z/)) &&
             (prefix.nil? || prefix.empty? || prefix.match?(/\A[A-Za-z_][A-Za-z0-9_.-]*\z/))
        raise SyntaxError, "nokogiri (spinel): unsupported CSS selector: #{c}"
      end
      return local if !prefix.nil? && prefix.empty?
      return prefix + ":" + local unless prefix.nil?
      return "*:" + local if mode == 2 && local != "*"
      return "xmlns:" + local if mode == 1 && local != "*"
      local
    end

    # The index of the `close` that ends the `open` at i, outside quotes.
    def self.closing(c, i, open, close)
      depth = 0
      quote = ""
      j = i
      while j < c.length
        ch = c[j]
        if quote != ""
          quote = "" if ch == quote
        elsif ch == "'" || ch == "\""
          quote = ch
        elsif ch == open
          depth += 1
        elsif ch == close
          depth -= 1
          return j if depth == 0
        end
        j += 1
      end
      raise SyntaxError, "nokogiri (spinel): unterminated '#{open}' in CSS selector: #{c}"
    end

    def self.css_class(hay, needle)
      "contains(concat(' ',normalize-space(#{hay}),' '),' #{needle} ')"
    end

    def self.pseudo_class(name)
      if name == "first" || name == "first-of-type"
        "position()=1"
      elsif name == "last" || name == "last-of-type"
        "position()=last()"
      elsif name == "first-child"
        "count(preceding-sibling::*)=0"
      elsif name == "last-child"
        "count(following-sibling::*)=0"
      elsif name == "only-child"
        "count(preceding-sibling::*)=0 and count(following-sibling::*)=0"
      elsif name == "only-of-type"
        "last()=1"
      elsif name == "empty"
        "not(node())"
      elsif name == "parent"
        "node()"
      elsif name == "root"
        "not(parent::*)"
      else
        custom_name(name)
        "nokogiri:#{name}(.)"
      end
    end

    def self.custom_name(name)
      raise SyntaxError, "Invalid XPath function name '#{name}'" if name.start_with?("-")
      nil
    end

    def self.function(name, arg, mode)
      int = arg.match?(/\A-?\d+\z/)
      if name == "not"
        negation(arg, mode)
      elsif name == "has"
        raise SyntaxError, "nokogiri (spinel): unsupported :has() with a selector list: #{arg}" if split_list(arg).length > 1
        body = one(arg, mode)
        body.start_with?("./") ? body : ".//" + body
      elsif name == "eq"
        "position()=#{arg}"
      elsif name == "gt"
        "position()>#{arg}"
      elsif name == "contains"
        "contains(.,#{arg})"
      elsif name == "nth" || name == "nth-of-type"
        int ? "position()=#{arg}" : nth(arg, false, false)
      elsif name == "nth-child"
        int ? "count(preceding-sibling::*)=#{arg.to_i - 1}" : nth(arg, true, false)
      elsif name == "nth-last-of-type"
        if int
          index = arg.to_i - 1
          index == 0 ? "position()=last()" : "position()=last()-#{index}"
        else
          nth(arg, false, true)
        end
      elsif name == "nth-last-child"
        int ? "count(following-sibling::*)=#{arg.to_i - 1}" : nth(arg, true, true)
      else
        custom_name(name)
        "nokogiri:#{name}(.,#{arg})"
      end
    end

    # :not(simple): the gem's `not(self::name)` for an element name, else
    # not(conditions). An element name WITH conditions the gem's parser
    # reduces to the name alone; rather than drop them, raise.
    def self.negation(arg, mode)
      if arg.empty? || split_list(arg).length > 1 || combinator?(arg)
        raise SyntaxError, "nokogiri (spinel): unsupported :not(#{arg})"
      end
      parts = compound_parts(arg, mode)
      if parts[1].empty?
        "not(self::#{parts[0].empty? ? "*" : parts[0]})"
      elsif parts[0].empty?
        "not(#{parts[1]})"
      else
        raise SyntaxError, "nokogiri (spinel): unsupported :not(#{arg}) (an element name with conditions)"
      end
    end

    # Whether a selector has a combinator outside quotes, brackets and
    # parentheses (so is more than one compound).
    def self.combinator?(sel)
      quote = ""
      depth = 0
      found = false
      sel.each_char do |ch|
        if quote != ""
          quote = "" if ch == quote
        elsif ch == "'" || ch == "\""
          quote = ch
        elsif ch == "[" || ch == "("
          depth += 1
        elsif ch == "]" || ch == ")"
          depth -= 1
        elsif depth == 0 && (ch == " " || ch == ">" || ch == "+" || ch == "~")
          found = true
        end
      end
      found
    end

    # an+b, as the gem writes it (XPathVisitor#nth, #read_a_and_positive_b).
    def self.nth(arg, child, last)
      s = arg.delete(" ")
      s = "2n+1" if s == "odd"
      s = "2n+0" if s == "even"
      m = s.match(/\A([+-]?\d*)n(?:([+-])(\d+))?\z/)
      raise SyntaxError, "nokogiri (spinel): unsupported an+b: #{arg}" if m.nil?
      a_s = m[1].to_s
      a = a_s == "" || a_s == "+" ? 1 : (a_s == "-" ? -1 : a_s.to_i)
      b = m[3].nil? ? 0 : m[3].to_s.to_i
      b = a - (b % a) if m[2] == "-"
      position = if child
                   last ? "(count(following-sibling::*)+1)" : "(count(preceding-sibling::*)+1)"
                 else
                   last ? "(last()-position()+1)" : "position()"
                 end
      return "(#{position} mod #{a})=0" if b == 0
      compare = a < 0 ? "<=" : ">="
      return "#{position}#{compare}#{b}" if a.abs == 1
      "(#{position}#{compare}#{b}) and (((#{position}-#{b}) mod #{a.abs})=0)"
    end

    # One attribute test. The value keeps the quotes it was written with,
    # as the gem's does (`[a='v']` → `@a='v'`, `[a="v"]` → `@a="v"`); a bare
    # value is written with single quotes.
    def self.attribute(body)
      m = body.match(/\A\s*([A-Za-z_:][A-Za-z0-9_:.-]*(?:\|[A-Za-z_][A-Za-z0-9_.-]*)?)\s*(?:([~|^$*!]?=)\s*(.+?))?\s*\z/)
      raise SyntaxError, "nokogiri (spinel): unsupported attribute selector: [#{body}]" if m.nil?
      name = "@" + m[1].to_s.sub("|", ":")
      op = m[2]
      return name if op.nil?
      raw = m[3].to_s
      lit = (raw.start_with?("'") || raw.start_with?("\"")) ? raw : "'#{raw}'"
      bare = lit[1...-1]
      if bare.include?(lit[0])
        lit = "concat(\"" + bare.split("\"", -1).join("\",'\"',\"") + "\",\"\")"
      end
      if op == "="
        "#{name}=#{lit}"
      elsif op == "!="
        "#{name}!=#{lit}"
      elsif op == "~="
        css_class(name, bare)
      elsif op == "|="
        "#{name}=#{lit} or starts-with(#{name},concat(#{lit},'-'))"
      elsif op == "^="
        "starts-with(#{name},#{lit})"
      elsif op == "$="
        "substring(#{name},string-length(#{name})-string-length(#{lit})+1,string-length(#{lit}))=#{lit}"
      else
        "contains(#{name},#{lit})"
      end
    end
  end

  module HTML4
    class Document < XML::Document
      # The gem's HTML4::Document.new: empty, with the default DTD and no
      # encoding.
      def initialize(ref = nil)
        @ref = ref.nil? ? NokoNodeRef.new.__new_html_document(false) : ref
      end

      # The gem's HTML4::Document.parse(string): the String's own encoding
      # (UTF-8) and ParseOptions::DEFAULT_HTML.
      def self.parse(html)
        ref = NokoNodeRef.new.__parse_html(html.to_s, "UTF-8", XML::ParseOptions::DEFAULT_HTML)
        new(ref)
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

    # The gem's HTML4 fragment. Without a context it is parsed as the gem
    # parses one: the input inside `<html><body>`, and the fragment is the
    # body's children (or the body itself when the input starts with one).
    # With one, inside a <div> in that node's context, the div's children.
    class DocumentFragment < XML::DocumentFragment
      def initialize(document, tags = nil, context = nil, options = XML::ParseOptions::DEFAULT_HTML)
        @errors = []
        s = tags.to_s
        if context.nil?
          path = s.match?(/\A\s*?<body/i) ? "/html/body" : "/html/body/node()"
          @doc = Document.parse("<html><body>" + s)
          @frag = XML::Node.new(@doc.__ref.__create_fragment)
          @doc.xpath(path).to_a.each { |child| @frag.__ref.__add_child(child.__ref) }
          @errors = @doc.errors
        else
          @doc = document
          @frag = XML::Node.new(document.__ref.__create_fragment)
          return if tags.nil?
          before = document.errors.length
          set = context.parse("<div>" + s + "</div>", options)
          unless set.empty?
            set.first.children.each { |child| @frag.__ref.__add_child(child.__ref) }
          end
          @errors = document.errors.drop(before)
        end
      end

      def self.parse(tags)
        DocumentFragment.new(nil, tags)
      end

      def to_s
        children.to_html
      end
    end

    def self.fragment(tags)
      DocumentFragment.parse(tags)
    end
  end

  HTML = HTML4

  # The gem's Nokogiri::HTML5(string, url, encoding, max_attributes:,
  # max_errors:, max_tree_depth:, parse_noscript_content_as_text:).
  def self.HTML5(html, url = nil, encoding = nil, max_attributes: Gumbo::DEFAULT_MAX_ATTRIBUTES,
                 max_errors: Gumbo::DEFAULT_MAX_ERRORS, max_tree_depth: Gumbo::DEFAULT_MAX_TREE_DEPTH,
                 parse_noscript_content_as_text: false)
    HTML5::Document.parse(html, url, encoding, max_attributes: max_attributes, max_errors: max_errors,
                          max_tree_depth: max_tree_depth, parse_noscript_content_as_text: parse_noscript_content_as_text)
  end

  module Gumbo
    DEFAULT_MAX_ATTRIBUTES = 400
    DEFAULT_MAX_ERRORS = 0
    DEFAULT_MAX_TREE_DEPTH = 400
  end

  # HTML5, parsed by gumbo (the parser Nokogiri vendors, which began as
  # nokogumbo) into the same libxml2 tree everything else here works on,
  # and serialized by the HTML standard's rules.
  module HTML5
    module QuirksMode
      NO_QUIRKS = 0
      QUIRKS = 1
      LIMITED_QUIRKS = 2
    end

    def self.parse(html, url = nil, encoding = nil, max_attributes: Gumbo::DEFAULT_MAX_ATTRIBUTES,
                   max_errors: Gumbo::DEFAULT_MAX_ERRORS, max_tree_depth: Gumbo::DEFAULT_MAX_TREE_DEPTH,
                   parse_noscript_content_as_text: false)
      Document.parse(html, url, encoding, max_attributes: max_attributes, max_errors: max_errors,
                     max_tree_depth: max_tree_depth, parse_noscript_content_as_text: parse_noscript_content_as_text)
    end

    def self.fragment(tags, encoding = nil, context: nil, max_attributes: Gumbo::DEFAULT_MAX_ATTRIBUTES,
                      max_errors: Gumbo::DEFAULT_MAX_ERRORS, max_tree_depth: Gumbo::DEFAULT_MAX_TREE_DEPTH,
                      parse_noscript_content_as_text: false)
      DocumentFragment.parse(tags, encoding, context: context, max_attributes: max_attributes,
                             max_errors: max_errors, max_tree_depth: max_tree_depth,
                             parse_noscript_content_as_text: parse_noscript_content_as_text)
    end

    class Document < HTML4::Document
      # The gem's HTML5::Document.new: HTML4's, marked HTML5.
      def initialize(ref = nil)
        @ref = ref.nil? ? NokoNodeRef.new.__new_html_document(true) : ref
      end

      # The gem's HTML5::Document.parse: a String (UTF-8), gumbo's limits
      # as keywords. A limit gumbo hits raises ArgumentError, as in the
      # gem; the errors are kept only up to max_errors (none by default).
      def self.parse(html, url = nil, encoding = nil, max_attributes: Gumbo::DEFAULT_MAX_ATTRIBUTES,
                     max_errors: Gumbo::DEFAULT_MAX_ERRORS, max_tree_depth: Gumbo::DEFAULT_MAX_TREE_DEPTH,
                     parse_noscript_content_as_text: false)
        ref = NokoNodeRef.new.__parse_html5(html.to_s, max_attributes, max_errors, max_tree_depth,
                                            parse_noscript_content_as_text)
        raise ArgumentError, NokogiriExt.sp_noko_gumbo_status unless ref.__present?
        new(ref)
      end

      def quirks_mode
        q = @ref.__quirks_mode
        q < 0 ? nil : q
      end

      # The gem's: an HTML5 fragment with no context.
      def fragment(tags = nil)
        DocumentFragment.new(self, tags)
      end
    end

    # The gem's HTML5 fragment: gumbo's fragment parse, in the context of a
    # tag name ("tr", "svg", "math:mi"; "body" by default) or of a node,
    # its errors its own.
    class DocumentFragment < HTML4::DocumentFragment
      def self.parse(tags, encoding = nil, context: nil, max_attributes: Gumbo::DEFAULT_MAX_ATTRIBUTES,
                     max_errors: Gumbo::DEFAULT_MAX_ERRORS, max_tree_depth: Gumbo::DEFAULT_MAX_TREE_DEPTH,
                     parse_noscript_content_as_text: false)
        doc = Document.new(NokoNodeRef.new.__new_html5_document)
        DocumentFragment.new(doc, tags, context, max_attributes: max_attributes, max_errors: max_errors,
                             max_tree_depth: max_tree_depth,
                             parse_noscript_content_as_text: parse_noscript_content_as_text)
      end

      def initialize(document, tags = nil, context = nil, max_attributes: Gumbo::DEFAULT_MAX_ATTRIBUTES,
                     max_errors: Gumbo::DEFAULT_MAX_ERRORS, max_tree_depth: Gumbo::DEFAULT_MAX_TREE_DEPTH,
                     parse_noscript_content_as_text: false)
        @doc = document
        @frag = XML::Node.new(document.__ref.__create_fragment)
        @errors = []
        return if tags.nil?
        ctx_tag = "body"
        ctx_ns = 0
        form = false
        encoding = ""
        is_node = false
        if context.is_a?(String)
          ctx_tag = context
          colon = ctx_tag.index(":")
          if colon.nil?
            ctx_ns = 1 if ctx_tag.downcase == "svg"
            ctx_ns = 2 if ctx_tag.downcase == "math"
          else
            prefix = ctx_tag[0...colon].downcase
            if prefix == "svg"
              ctx_ns = 1
            elsif prefix == "math"
              ctx_ns = 2
            elsif prefix != "html"
              raise ArgumentError, "Invalid context namespace '#{ctx_tag[0...colon]}'"
            end
            ctx_tag = ctx_tag[(colon + 1)..]
          end
          form = ctx_ns == 0 && ctx_tag.downcase == "form"
        elsif !context.nil?
          is_node = true
          ctx_tag = context.name
          ctx_ns = DocumentFragment.namespace_of(context, true)
          node = context
          while node
            if node.element? && node.name.downcase == "form" && DocumentFragment.namespace_of(node, false) == 0
              form = true
              break
            end
            node = node.parent
          end
          if ctx_ns == 2 && ctx_tag.downcase == "annotation-xml"
            encoding = context["encoding"].to_s
          end
        end
        r = @frag.__ref.__html5_fragment(tags.to_s, ctx_tag, ctx_ns, form, encoding, is_node,
                                         max_attributes, max_errors, max_tree_depth,
                                         parse_noscript_content_as_text)
        raise ArgumentError, NokogiriExt.sp_noko_gumbo_status if r < 0
        i = 0
        n = NokogiriExt.sp_noko_parse_error_count
        while i < n
          @errors << XML::SyntaxError.build(NokogiriExt.sp_noko_parse_error_message(i),
                                            NokogiriExt.sp_noko_parse_error_level(i),
                                            NokogiriExt.sp_noko_parse_error_line(i),
                                            NokogiriExt.sp_noko_parse_error_column(i))
          i += 1
        end
      end

      # gumbo's namespace for a node: HTML (0), SVG (1), MathML (2); with
      # `known`, anything else raises, as the gem's lookup_namespace does.
      def self.namespace_of(node, known)
        ns = node.namespace
        return 0 if ns.nil?
        href = ns.href
        return 0 if href == "http://www.w3.org/1999/xhtml"
        return 2 if href == "http://www.w3.org/1998/Math/MathML"
        return 1 if href == "http://www.w3.org/2000/svg"
        raise ArgumentError, "Unexpected namespace URI \"#{href}\"" if known
        -1
      end
    end
  end
end
