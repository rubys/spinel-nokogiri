# CSS beyond the basics: the sibling combinators (`+`, `~`), a leading
# combinator (`node.css("> li")`), and the pseudo-classes the gem writes
# as plain XPath — structural (`:first-child`, `:nth-child(2n+1)`,
# `:last-of-type`, …), `:not`, `:has`, `:contains`, `:empty`, `:root`, and
# jQuery's `:first` / `:eq` / `:gt`. The ones the gem hands to a custom
# handler (`:even`, `:checked`) raise the gem's XPath error. Every line is
# the gem's answer.
require "nokogiri"

PAGE = <<~HTML
  <html><body>
  <div id="a">
    <h2>Head</h2>
    <p class="x">p1</p>
    <p>p2 <b>bold</b></p>
    <span>s1</span>
    <p class="x y">p3</p>
    <p class="y"></p>
  </div>
  <ul>
    <li>l1</li><li class="x">l2</li><li>l3</li><li class="x">l4</li><li>l5</li><li>l6</li><li>l7</li>
  </ul>
  <ol><li>only</li></ol>
  <form><input name="a" checked><input name="b" disabled><a href="/in">in</a><a href="https://out">out</a></form>
  </body></html>
HTML

doc = Nokogiri::HTML(PAGE)

def show(doc, sel)
  puts (sel + " => " + doc.css(sel).map { |n| n.name + ":" + n.text.strip }.inspect)
end

[
  "h2 + p", "p + p", "h2 ~ p", "span ~ p", "div > p + span", "h2 ~ .y",
  "li:first-child", "li:last-child", "li:only-child", "p:first-of-type",
  "p:last-of-type", "span:only-of-type", "li:nth-child(2)", "li:nth-child(odd)",
  "li:nth-child(even)", "li:nth-child(3n)", "li:nth-child(3n+1)", "li:nth-child(-n+3)",
  "li:nth-child(n+5)", "li:nth-child(2n-1)", "li:nth-child( 2n + 1 )",
  "li:nth-last-child(2)", "li:nth-last-child(odd)", "p:nth-of-type(2)",
  "p:nth-of-type(2n)", "p:nth-last-of-type(1)", "p:nth-last-of-type(2)",
  "p:empty", "p:parent", ":root", "li:not(.x)", "p:not([class])", "p:not(.x.y)",
  "li:not(:first-child)", ":not(li):not(p):not(input):not(a):not(html):not(body):not(div):not(ul):not(ol):not(form):not(span):not(head)",
  "p:contains('p2')", "p:contains(\"p\")", "li:first", "li:last", "li:eq(3)",
  "li:nth(3)", "li:gt(5)", "div:has(b)", "div:has(> span)", "p:has(b)",
  "li.x:first", "li.x:first-of-type", "li.x:nth-of-type(2)", "li.x:last",
  "p.x:first-child", "*:first-child", "div > :first-child",
  "a[href]:not([href^=\"http\"])", "a[href!='/in']", "p[class~=\"y\"]:last-child",
  "ul li:nth-child(2), ol li",
].each { |sel| show(doc, sel) }

ul = doc.at_css("ul")
puts ul.css("> li").length.inspect
puts ul.css("> li.x").map { |n| n.text }.inspect
h2 = doc.at_css("h2")
puts h2.css("+ p").map { |n| n.text }.inspect
puts h2.css("~ p").length.inspect
puts doc.css("p").css("> b").map { |n| n.text }.inspect

["li:even", "input:checked", "li:lt(2)"].each do |sel|
  begin
    doc.css(sel)
    puts sel + " => no error"
  rescue Nokogiri::XML::XPath::SyntaxError => err
    puts sel + " => " + err.message
  end
end

x = Nokogiri::XML("<r xmlns=\"u\"><a/><b/><a/><c><a/></c></r>")
puts x.css("a + b").length.inspect
puts x.css("b ~ a").length.inspect
puts x.css("a:first-child").length.inspect
puts x.css("r > :not(a)").map { |n| n.name }.inspect
puts x.css("r:has(> c)").length.inspect
