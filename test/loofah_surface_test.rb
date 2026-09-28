# The nokogiri surface Loofah and rails-html-sanitizer stand on: document
# and fragment subclasses that parse as themselves, empty documents made
# with `new`, live attribute nodes (Loofah edits and removes them one by
# one), text and CDATA nodes made in a document, the node-type constants
# on Node, and a fragment searched from the fragment node. Every line is
# the gem's answer.
require "nokogiri"

class MyHTML4 < Nokogiri::HTML4::Document
  def kind
    "my html4"
  end
end

class MyHTML5 < Nokogiri::HTML5::Document
  def kind
    "my html5"
  end
end

class MyXML < Nokogiri::XML::Document
  def kind
    "my xml"
  end
end

class MyFragment4 < Nokogiri::HTML4::DocumentFragment
  def kind
    "my fragment4"
  end
end

class MyFragment5 < Nokogiri::HTML5::DocumentFragment
  def kind
    "my fragment5"
  end
end

puts "-- subclasses parse as themselves"
d4 = MyHTML4.parse("<p>four</p>")
puts d4.kind
puts d4.at_css("p").text
d5 = MyHTML5.parse("<p>five</p>")
puts d5.kind
puts d5.at_css("p").text
dx = MyXML.parse("<r><x>ex</x></r>")
puts dx.kind
puts dx.root.name

puts "-- new documents, and fragments made in them"
[MyHTML4.new, MyHTML5.new].each do |doc|
  puts doc.encoding.inspect
  doc.encoding = "UTF-8"
  puts doc.encoding.inspect
  puts doc.html?
  puts doc.children.length
end
x = Nokogiri::XML::Document.new
puts x.xml?
puts x.version.inspect

h4 = MyHTML4.new
h4.encoding = "UTF-8"
f4 = MyFragment4.new(h4, "<b>bold</b> and <i>it</i>")
puts f4.kind
puts f4.to_s
puts f4.children.length

h5 = MyHTML5.new
h5.encoding = "UTF-8"
f5 = MyFragment5.new(h5, "<b>bold</b> and <svg><a xlink:href=\"#x\">l</a></svg>")
puts f5.kind
puts f5.to_s
puts f5.children.length

puts "-- node types on Node"
el = f5.children.first
puts el.type
puts el.type == Nokogiri::XML::Node::ELEMENT_NODE
puts f5.children[1].type == Nokogiri::XML::Node::TEXT_NODE
puts Nokogiri::XML::Node::CDATA_SECTION_NODE
puts Nokogiri::XML::Node::COMMENT_NODE

puts "-- attribute nodes"
frag = Nokogiri::HTML5.fragment("<a href=\"/x\" style=\"color: red\" onclick=\"evil()\" title=\"t\">a</a>" \
                                "<svg><use xlink:href=\"#icon\" href=\"#h\"></use></svg>")
a = frag.at_css("a")
a.attribute_nodes.each do |attr|
  ns = attr.namespace
  puts [attr.name, attr.node_name, attr.value, attr.to_s, ns.nil? ? nil : ns.prefix].inspect
end
use = frag.at_xpath(".//svg:use", "svg" => "http://www.w3.org/2000/svg")
use.attribute_nodes.each do |attr|
  ns = attr.namespace
  puts [attr.name, attr.value, ns.nil? ? nil : ns.prefix, ns.nil? ? nil : ns.href].inspect
end

a.attribute_nodes.each do |attr|
  attr.remove if attr.name == "onclick"
end
puts a.to_html

style = a.attributes["style"]
style.value = "color:red;"
puts a.to_html
puts a.attributes["style"].value

href = a.attribute("href")
href.value = "/a b\"c<d>&amp;"
puts a["href"].inspect
puts a.to_html

title = a.attribute_nodes.find { |attr| attr.name == "title" }
title.value = ""
puts a.to_html
puts a.attribute("nope").inspect

puts "-- text and CDATA nodes"
doc = Nokogiri::HTML5::Document.parse("<p><b>x</b></p>")
b = doc.at_css("b")
t = Nokogiri::XML::Text.new("<b>x</b> & more", doc)
puts t.text?
puts t.content
b.add_next_sibling(t)
puts doc.at_css("p").inner_html
b.remove
puts doc.at_css("p").inner_html
xdoc = Nokogiri::XML("<r><c/></r>")
c = xdoc.create_cdata("a < b && c")
puts c.cdata?
puts c.content
xdoc.at_xpath("//c").add_child(c)
puts xdoc.root.to_xml
tx = xdoc.create_text_node("plain")
xdoc.at_xpath("//c").before(tx)
puts xdoc.root.to_xml

puts "-- encode_special_chars"
puts b.encode_special_chars("<a href=\"x\">&amp; 'q'</a>")

puts "-- fragments searched from the fragment node"
fb = Nokogiri::HTML4::DocumentFragment.parse("  <body><p>in body</p></body>")
puts fb.at_xpath("./body").nil?
puts fb.at_xpath("./body").children.to_s
puts fb.xpath("./p").length
fp = Nokogiri::HTML4::DocumentFragment.parse("<p>one</p><p>two</p>")
puts fp.at_xpath("./body").inspect
puts fp.xpath("./p").length
puts fp.xpath("./p").map { |n| n.text }.inspect
puts fp.xml?
puts fp.to_html(encoding: "UTF-8")
f5b = Nokogiri::HTML5::DocumentFragment.parse("<i>x</i><i>y</i>")
puts f5b.xpath("./i").length
puts f5b.to_html(encoding: "UTF-8")

puts "-- a fragment's copy is its own"
orig = Nokogiri::HTML5::DocumentFragment.parse("<p>one <b>two</b></p>")
copy = orig.dup
copy.at_css("b").remove
puts orig.to_s
puts copy.to_s

puts "-- parent="
pd = Nokogiri::HTML5::Document.parse("<div id=\"a\"></div><div id=\"b\"><span>s</span></div>")
span = pd.at_css("span")
span.parent = pd.at_css("#a")
puts pd.at_css("body").inner_html

puts "-- the version answers Loofah asks"
puts Nokogiri.uses_gumbo?
puts Nokogiri.jruby?.inspect
puts !!Nokogiri::VersionInfo.instance.libxml2?
puts Nokogiri::VERSION.split(".").first(2).join(".")
