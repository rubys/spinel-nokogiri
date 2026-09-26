# Nokogiri::XML — XML documents, namespaces, and the XML serializer: an
# Atom feed with a default and a prefixed namespace (CSS and XPath both
# implicitly bound to the root's namespaces, as the gem binds them), an RSS
# feed with none, CDATA / comment / processing-instruction nodes, parse
# errors in recover and strict mode, and remove_namespaces!. Every line is
# the gem's answer.
require "nokogiri"

ATOM = <<~XML
  <?xml version="1.0" encoding="utf-8"?>
  <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
    <title>T &amp; U</title>
    <entry><id>1</id><link href="/a" rel="alternate"/><media:thumbnail url="t.png"/><content type="html"><![CDATA[<p>hi</p>]]></content></entry>
    <entry><id>2</id><link href="/b"/></entry>
    <!-- c -->
    <?pi data?>
  </feed>
XML

def pairs(h)
  h.keys.map { |k| k + "=" + h[k] }.join(" ")
end

d = Nokogiri::XML(ATOM)
puts d.xml?.inspect
puts d.html?.inspect
puts d.root.name.inspect
puts pairs(d.root.namespaces).inspect
puts d.encoding.inspect
puts d.version.inspect
puts d.css("entry link").map { |l| l["href"] }.inspect
puts d.css("entry > id").map { |n| n.text }.inspect
puts d.at_css("feed > title").text.inspect
puts d.xpath("//xmlns:entry/xmlns:id").map { |n| n.text }.inspect
puts d.xpath("//entry").length.inspect
puts d.css("media|thumbnail").map { |n| n.name + " " + n["url"].to_s }.inspect
puts d.xpath("//media:thumbnail").map { |n| n.namespace.prefix.to_s + " " + n.namespace.href }.inspect
puts d.xpath("//m:thumbnail", { "m" => "http://search.yahoo.com/mrss/" }).length.inspect
puts d.root.namespace.prefix.inspect
puts d.root.namespace.href.inspect
puts pairs(d.at_css("entry").namespaces).inspect
puts d.root.namespace_definitions.map { |n| n.prefix.to_s + "=" + n.href }.inspect
puts d.at_css("entry").namespace_definitions.length.inspect
cd = d.at_css("content").children.first
puts [cd.node_type, cd.name, cd.text, cd.cdata?].inspect
puts d.root.children.map { |c| c.node_type.to_s + ":" + c.name }.inspect
puts d.root.children.select { |c| c.processing_instruction? }.map { |c| c.content }.inspect
puts d.at_css("title").to_s.inspect
puts d.at_css("title").to_xml.inspect
puts d.at_css("entry").to_s.inspect
puts d.to_xml.inspect
puts d.to_s.inspect
begin
  d.xpath("//a:x")
rescue Nokogiri::XML::XPath::SyntaxError => e
  puts e.message.inspect
end
begin
  d.xpath("//[")
rescue Nokogiri::XML::XPath::SyntaxError => e
  puts e.message.inspect
end

RSS = <<~XML
  <?xml version="1.0"?>
  <rss version="2.0"><channel><title>Chan</title>
  <item><title>One</title><link>https://a.test/1</link></item>
  <item><title>Two</title><link>https://a.test/2</link><Title>case</Title></item>
  </channel></rss>
XML

r = Nokogiri::XML::Document.parse(RSS)
puts r.at_xpath("//channel/title").text.inspect
puts r.css("item title").map { |n| n.text }.inspect
puts r.css("item Title").map { |n| n.text }.inspect
puts r.css("item > link").map { |n| n.text }.inspect
puts r.root["version"].inspect
puts pairs(r.root.namespaces).inspect
puts r.root.namespace.nil?.inspect
puts r.encoding.inspect
item = r.create_element("item")
t = r.create_element("title")
t.content = "Three & <more>"
item.add_child(t)
r.at_css("channel").add_child(item)
puts r.at_css("channel").to_xml.inspect

x = Nokogiri::XML("<a><B>x</B><b>y</b><br/></a>")
puts x.css("B").map { |n| n.text }.inspect
puts x.to_s.inspect
puts x.root.to_html.inspect
puts Nokogiri::XML("").to_s.inspect
puts Nokogiri::XML("").root.nil?.inspect
puts Nokogiri::XML("not xml").root.nil?.inspect

bad = Nokogiri::XML("<a>&bogus;<b></a>")
puts bad.to_s.inspect
puts bad.errors.map { |e| e.to_s }.inspect
puts bad.errors.map { |e| [e.level, e.line, e.column] }.inspect
puts ATOM.length.to_s + " " + d.errors.length.to_s
begin
  Nokogiri::XML("<a><b></a>", nil, nil, 0)
rescue Nokogiri::XML::SyntaxError => e
  puts ["strict", e.to_s, e.line, e.column, e.level].inspect
end
begin
  Nokogiri::XML("<a><b></a>") { |c| c.strict }
rescue Nokogiri::XML::SyntaxError => e
  puts ["block", e.message].inspect
end
nb = Nokogiri::XML("<a>\n  <b>x</b>\n</a>") { |c| c.noblanks }
puts nb.root.children.length.inspect

d.remove_namespaces!
puts d.xpath("//entry/id").map { |n| n.text }.inspect
puts d.at_css("thumbnail").name.inspect
puts pairs(d.root.namespaces).inspect
puts d.at_css("entry").to_s.inspect

# A reparented element takes the namespace its name resolves to where it
# lands (the gem's relink_namespace): the default one, or a prefix's.
f = Nokogiri::XML("<feed xmlns=\"http://www.w3.org/2005/Atom\" xmlns:m=\"mm\"><entry/></feed>")
entry = f.create_element("entry")
f.root.add_child(entry)
puts entry.namespace.href.inspect
puts f.css("entry").length.inspect
th = f.create_element("m:thumb")
entry.add_next_sibling(th)
puts [th.name, th.namespace.prefix, th.namespace.href].inspect
puts f.xpath("//m:thumb").length.inspect
puts f.root.to_xml.inspect
