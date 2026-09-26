# Markup where a node is expected: the gem parses a String in the context
# of the node it is going into (Node#parse, libxml2's
# xmlParseInNodeContext), so add_child("<td>…") under a <tr> makes a
# cell. inner_html= / children=, add_child, the sibling adds, before /
# after, replace, wrap, prepend_child, fragments with and without a
# context, and nodes moved between documents (copied in, as the gem copies
# them) or out of their place (a text node too). Every line is the gem's
# answer.
require "nokogiri"

doc = Nokogiri::HTML(<<~HTML)
  <html><body>
  <div id="d"><p id="p1">one <b>two</b> three</p><p id="p2">four</p></div>
  <table><tr id="r"><td>a</td></tr></table>
  <ul id="u"><li>x</li></ul>
  </body></html>
HTML

div = doc.at_css("#d")
p1 = doc.at_css("#p1")
added = p1.add_child("<i>i1</i> and <i>i2</i>")
puts [added.class.to_s, added.length].inspect
puts p1.to_html.inspect
p1.inner_html = "<em>replaced</em> text"
puts p1.to_html.inspect
p1.children = "plain & <br> after"
puts p1.to_html.inspect
doc.at_css("#r").add_child("<td>b</td><td>c</td>")
puts doc.at_css("table").to_html.inspect
puts doc.at_css("#u").add_child("<li>y</li>").map { |n| n.name }.inspect
p2 = doc.at_css("#p2")
p2.add_previous_sibling("<hr>")
p2.add_next_sibling("tail <b>t</b>")
puts div.inner_html.inspect
p2.before("<h3>B</h3>").after("<h4>A</h4>")
puts div.inner_html.inspect
r = p2.replace("<p id=\"p3\">new</p><p>newer</p>")
puts r.length.inspect
puts div.inner_html.inspect
doc.at_css("h3").replace("<h2>two</h2>")
puts div.inner_html.inspect
t = doc.at_css("h2").children.first
t.replace("<b>bold</b>")
puts doc.at_css("h2").to_html.inspect
doc.at_css("h4").wrap("<section class=\"w\"></section>")
puts div.inner_html.inspect
doc.at_css("#p3").wrap(doc.create_element("article"))
puts div.inner_html.inspect
doc.at_css("#u").prepend_child("<li>first</li>")
puts doc.at_css("#u").to_html.inspect
set = div.parse("<span>s1</span><span>s2</span>")
puts [set.length, set.first.parent.nil?].inspect
puts doc.at_css("tr").fragment("<td>ctx</td>").children.map { |n| n.name }.inspect
puts doc.fragment("<p>df</p>").to_html.inspect
puts doc.at_css("#u").children.last.swap("<li>swapped</li>").name.inspect
puts doc.at_css("#u").inner_html.inspect

# a text node moves (the gem inserts a copy and takes the original out)
h2 = doc.at_css("h2")
text = p1.children.first
h2.add_child(text)
puts [p1.to_html, h2.to_html].inspect
puts text.parent.name.inspect

# nodes from another document are copied in
other = Nokogiri::HTML("<p class=\"o\">from <i>other</i></p>")
op = other.at_css("p")
doc.at_css("body").add_child(op)
puts doc.css("p.o").length.inspect
puts other.css("p.o").length.inspect
puts op.parent.name.inspect
puts (op.document == doc).inspect
frag = Nokogiri::HTML.fragment("<em>f1</em><em>f2</em>")
doc.at_css("#u").add_child(frag)
puts doc.css("#u em").map { |n| n.text }.inspect
doc.at_css("#u").add_child(Nokogiri::HTML.fragment("<em>f3</em>").children)
puts doc.css("#u em").length.inspect

x = Nokogiri::XML("<feed xmlns=\"http://www.w3.org/2005/Atom\" xmlns:m=\"mm\"><entry><id>1</id></entry></feed>")
entry = x.at_css("entry")
entry.add_child("<title>T</title><m:thumb url=\"u\"/>")
puts entry.to_xml.inspect
puts x.css("entry title").length.inspect
puts x.xpath("//m:thumb").first["url"].inspect
entry.inner_html = "<id>2</id>"
puts entry.to_xml.inspect
puts x.at_css("id").namespace.href.inspect
f = Nokogiri::XML.fragment("<a>1</a><b/>")
puts [f.children.length, f.to_s].inspect
puts x.fragment("<link href=\"/l\"/>").children.first.name.inspect
bad = entry.add_child("<a><b></a>")
puts [bad.length, entry.to_xml].inspect
puts x.errors.length.inspect
