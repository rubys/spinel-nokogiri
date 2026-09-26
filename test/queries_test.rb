# The rest of the surface real apps use, answer by answer against the gem:
# lobsters' og: meta lookups (StoryImage, Story#fetched_attributes) and
# webmention discovery (NodeSet#css over `self::`), campfire's Opengraph
# XPath, the CSS subset, attributes, text, content= escaping, replace with
# a NodeSet, and whole-document serialization.
require "nokogiri"

PAGE = <<~HTML
  <!DOCTYPE html>
  <html lang="en"><head>
  <meta charset="utf-8">
  <title>A &amp; B — café</title>
  <meta property="og:title" content="The Title">
  <meta property="og:image" content="https://img.test/i.png">
  <meta name="og:description" content="Desc &quot;q&quot;">
  <meta name="image" content="/fallback.png">
  <link rel="webmention" href="https://wm.test/endpoint">
  <link rel="stylesheet alternate" href="/s.css">
  </head><body>
  <div id="main" class="a b"><p class="x">one <b>two</b> <a href="/l1">l1</a></p>
  <ul><li>i1</li><li class="x">i2</li></ul>
  <p>two<br>three <img src="/p.png" alt="pic"></p></div>
  <a rel="http://webmention.org/" href="/old">old</a>
  </body></html>
HTML

doc = Nokogiri::HTML(PAGE)
puts doc.at_css("meta[property='og:image']")&.attributes&.[]("content")&.text.inspect
puts doc.at_css("meta[name='image']")&.attributes&.[]("content")&.text.inspect
puts doc.at_css("meta[property='og:missing']").inspect
puts doc.css('[rel~="webmention"]').css("[href]").attribute("href").value.inspect
puts doc.css('[rel="http://webmention.org/"]').css("[href]").attribute("href").value.inspect
puts doc.css('[rel="http://webmention.org"]').css("[href]").empty?.inspect
tags = doc.xpath("//*/meta[starts-with(@property, \"og:\") or starts-with(@name, \"og:\")]")
puts tags.map { |t| [t["property"] || t["name"], t["content"]] }.inspect
puts doc.css("title").text.inspect
puts doc.css("p.x, li.x").map { |n| n.name + ":" + n.text }.inspect
puts doc.css("#main > p").length.inspect
puts doc.css("div p b").map { |n| n.to_html }.inspect
puts doc.css("ul > li").map { |n| n.text }.inspect
puts doc.css("[href^=\"/l\"], [href$=\".css\"], [href*=\"old\"]").map { |n| n["href"] }.inspect
puts doc.at_css("div")["class"].inspect
puts doc.at_css("div").key?("id").inspect
puts doc.at_css("div")["nope"].inspect
puts doc.at_css("p").attributes.keys.inspect
puts doc.search("li").length.inspect
puts doc.search("//li").length.inspect
puts doc.at_css("body").children.length.inspect
puts doc.at_css("ul").children.map { |c| c.name }.inspect

# content= escapes; replace with a NodeSet (the node's own children)
p1 = doc.at_css("p")
b = p1.at_css("b")
b.replace(b.children)
puts p1.to_html.inspect
li = doc.at_css("li")
li.content = "<script>x</script> & more"
puts li.to_html.inspect
a = doc.create_element("a")
a["href"] = "/new"
a.content = "new"
doc.at_css("img").replace(a)
puts doc.at_css("div").inner_html.inspect
h = doc.at_css("p")
h.name = "strong"
puts h.to_html.inspect

# whole documents
puts Nokogiri::HTML("<p>x</p>").to_html.inspect
puts Nokogiri::HTML("").to_html.inspect
puts Nokogiri::HTML("plain text").at_css("body").inner_html.inspect
puts Nokogiri::HTML("<p>unclosed <b>bold").at_css("body").inner_html.inspect
puts Nokogiri::HTML("<table><td>cell</table>").at_css("body").inner_html.inspect
puts Nokogiri::HTML("<p>&nbsp;&copy;&#x1F600;&lt;&gt;&amp;</p>").at_css("p").inner_html.inspect
puts Nokogiri::HTML("<p>x</p>").at_css("body").nil?.inspect
puts Nokogiri::HTML("").at_css("body").nil?.inspect
begin
  doc.xpath("//[")
rescue Nokogiri::XML::XPath::SyntaxError => e
  puts "syntax error raised"
end
