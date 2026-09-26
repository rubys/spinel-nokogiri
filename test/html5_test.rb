# Nokogiri::HTML5 — gumbo, the HTML5 parser Nokogiri vendors (it began as
# nokogumbo): the spec's tree construction (misnested tags, foster
# parenting, implied elements), SVG and MathML in their namespaces, the
# HTML standard's serialization, quirks mode, errors when asked for
# (max_errors), limits, fragments with and without a context (a string or
# a node), markup in context when editing, and CSS over it (element names
# in any namespace, as the gem writes them). Every line is the gem's
# answer.
require "nokogiri"

PAGE = <<~HTML
  <!DOCTYPE html>
  <html lang="en"><head><meta charset="utf-8"><title>T &amp; U</title>
  <script>if (a < b && c > d) { x = "</p>" }</script></head>
  <body>
  <p class="x">one&nbsp;two <br> three <img src="/i.png" alt='say "hi"'>
  <svg viewBox="0 0 10 10"><circle r="4"/><foreignObject><p>in svg</p></foreignObject></svg>
  <math><mi>x</mi></math>
  <table><tr><td>a</td></tr>foster</table>
  <b><i>bold italic</b> italic</i>
  <textarea>
  kept</textarea>
  <template><li>t</li></template>
  </body></html>
HTML

doc = Nokogiri::HTML5(PAGE)
puts doc.class.to_s
puts doc.quirks_mode.inspect
puts doc.encoding.inspect
puts doc.html?.inspect
puts doc.to_html.inspect
puts doc.at_css("body").inner_html.inspect
puts doc.at_css("p").to_html.inspect
puts doc.at_css("title").text.inspect
puts doc.at_css("script").text.inspect
puts doc.css("circle").length.inspect
puts doc.at_css("circle").namespace.href.inspect
puts doc.at_css("svg").namespace.prefix.inspect
puts doc.at_css("svg")["viewBox"].inspect
puts doc.css("svg p").map { |n| n.text }.inspect
puts doc.at_css("mi").namespace.href.inspect
puts doc.css("body > *").map { |n| n.name }.inspect
puts doc.at_css("table").to_html.inspect
puts doc.at_css("p").children.map { |n| n.name }.inspect
puts doc.at_css("meta").document.class.to_s
puts doc.meta_encoding.inspect
puts doc.errors.length.inspect

[
  "<p>no doctype",
  "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\"><p>x",
  "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\"><p>x",
  "",
].each do |html|
  d = Nokogiri::HTML5(html)
  puts [d.quirks_mode, d.to_html].inspect
end

bad = Nokogiri::HTML5("<p>x</b><div><p>y", max_errors: 10)
puts bad.errors.length.inspect
puts bad.errors.map { |e| [e.line, e.column, e.level] }.inspect
puts bad.errors.first.to_s.inspect
puts Nokogiri::HTML5("<p>x</b>").errors.length.inspect
begin
  Nokogiri::HTML5("<div>" * 5 + "x", max_tree_depth: 3)
rescue ArgumentError => err
  puts ["depth", err.message].inspect
end
begin
  Nokogiri::HTML5("<p a=1 b=2 c=3>", max_attributes: 2)
rescue ArgumentError => err
  puts ["attrs", err.message].inspect
end

f = Nokogiri::HTML5.fragment("<td>cell</td><p>para</p>")
puts [f.children.length, f.to_html].inspect
f = Nokogiri::HTML5.fragment("<td>cell</td>", context: "tr")
puts f.to_html.inspect
f = Nokogiri::HTML5.fragment("<circle r=\"1\"/>", context: "svg")
puts [f.to_html, f.children.first.namespace.href].inspect
f = Nokogiri::HTML5.fragment("<b>x</i>", max_errors: 5)
puts [f.to_html, f.errors.length].inspect
puts Nokogiri::HTML5.fragment("a &amp; b <!-- c -->").to_html.inspect
puts doc.fragment("<li>one</li>").to_html.inspect

tr = doc.at_css("tr")
tr.add_child("<td>b</td><td>c</td>")
puts doc.at_css("table").to_html.inspect
p1 = doc.at_css("p")
p1.inner_html = "<em>new</em> &amp; <svg><rect/></svg>"
puts p1.to_html.inspect
puts doc.css("rect").length.inspect
doc.at_css("em").replace("<strong>s</strong>")
puts p1.inner_html.inspect
puts doc.css("td:last-child, em, strong").map { |n| n.name }.inspect
puts doc.at_css("textarea").to_html.inspect
puts doc.at_css("template").to_html.inspect
