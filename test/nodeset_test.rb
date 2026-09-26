# NodeSet as the gem's Enumerable NodeSet (each_with_index, reject,
# each_slice, group_by, inject, …, with the gem's Array-vs-NodeSet
# answers), its set operations and bulk edits, and the Node conveniences
# code reaches for next: ancestors, traverse, classes and add_class /
# remove_class, matches?, element siblings, path, line, blank?. Every
# line is the gem's answer.
require "nokogiri"

doc = Nokogiri::HTML(<<~HTML)
  <html><body>
  <div id="d" class="box wide">
    <ul>
      <li class="a">one</li>
      <li class="b">two</li>
      <li class="a b">three</li>
      <li>four</li>
      <li class="c">five</li>
    </ul>
    <p>para <em>em</em></p>
  </div>
  </body></html>
HTML

lis = doc.css("li")
names = lis.map { |n| n.text }
puts names.inspect
lis.each_with_index { |n, i| puts "#{i}:#{n.text}" if i.odd? }
puts lis.reject { |n| n["class"].nil? }.map { |n| n.text }.inspect
puts lis.select { |n| n.text.length == 4 }.class.inspect
puts lis.find_all { |n| n.text.include?("o") }.map { |n| n.text }.inspect
puts lis.detect { |n| n.text.start_with?("t") }.text.inspect
puts lis.find_index { |n| n.text == "three" }.inspect
puts lis.index(doc.at_css("li.c")).inspect
puts lis.include?(doc.at_css("li.b")).inspect
puts lis.include?(doc.at_css("p")).inspect
puts lis.any? { |n| n.text == "five" }.inspect
puts lis.all? { |n| n.name == "li" }.inspect
puts lis.none? { |n| n.text == "six" }.inspect
puts lis.count { |n| n.text.length > 3 }.inspect
puts lis.first(2).map { |n| n.text }.inspect
puts lis.first(9).length.inspect
puts lis.take(3).map { |n| n.text }.inspect
puts lis.drop(3).map { |n| n.text }.inspect
lis.each_slice(2) { |pair| puts pair.map { |n| n.text }.join("+") }
puts lis.group_by { |n| n.text.length }.map { |k, v| "#{k}=#{v.length}" }.inspect
puts lis.partition { |n| n.key?("class") }.map { |part| part.length }.inspect
puts lis.sort_by { |n| n.text }.map { |n| n.text }.inspect
puts lis.min_by { |n| n.text }.text.inspect
puts lis.max_by { |n| n.text.length }.text.inspect
puts lis.inject(0) { |sum, n| sum + n.text.length }.inspect
puts lis.flat_map { |n| n.classes }.inspect
puts lis.filter_map { |n| n["class"] }.inspect
puts lis.each_with_object([]) { |n, acc| acc << n.text.upcase }.inspect
puts lis.to_a.length.inspect
puts lis.last.text.inspect
puts lis[1].text.inspect
puts lis[-1].text.inspect
puts lis[1, 2].map { |n| n.text }.inspect
puts lis[1..2].map { |n| n.text }.inspect
puts lis.slice(3, 5).length.inspect
puts lis.reverse.map { |n| n.text }.inspect
puts lis.filter(".a").map { |n| n.text }.inspect

a = doc.css("li.a")
b = doc.css("li.b")
puts (a | b).map { |n| n.text }.inspect
puts (a + b).length.inspect
puts (a & b).map { |n| n.text }.inspect
puts (a - b).map { |n| n.text }.inspect
puts (a == doc.css(".a")).inspect
puts (a == b).inspect
s = doc.css("li.c")
s << doc.at_css("p")
s.push(doc.at_css("em"))
puts s.map { |n| n.name }.inspect
puts s.pop.name.inspect
puts s.shift.name.inspect
puts s.length.inspect
puts s.delete(doc.at_css("p")).name.inspect
puts s.empty?.inspect
puts doc.css("ul").children.length.inspect
puts doc.css("p").children.map { |n| n.name }.inspect
puts lis.inner_text.inspect
puts doc.css("em").to_xml.inspect
puts lis.at_xpath("self::li[@class='c']").text.inspect
puts lis.at("em").inspect
puts doc.css("p").at("em").text.inspect

lis.add_class("item")
puts lis.map { |n| n["class"] }.inspect
lis.remove_class("a")
puts lis.map { |n| n["class"] }.inspect
lis.append_class("item")
puts lis.first["class"].inspect
doc.css("li.c").remove_class
puts doc.at_css("li:last-child").key?("class").inspect
lis.attr("data-x", "1")
puts lis.map { |n| n["data-x"] }.uniq.inspect
puts lis.attr("data-x").value.inspect
lis.set("data-y", "2")
lis.remove_attr("data-x")
puts lis.first.keys.inspect

d = doc.at_css("div")
puts d.classes.inspect
d.add_class("wide tall")
puts d["class"].inspect
d.append_class(["box", "x"])
puts d["class"].inspect
d.remove_class(["box", "x"])
puts d["class"].inspect
d.remove_class("wide tall")
puts d.key?("class").inspect
em = doc.at_css("em")
puts em.ancestors.map { |n| n.name }.inspect
puts em.ancestors("div").map { |n| n["id"] }.inspect
puts em.ancestors("#nope").length.inspect
order = []
doc.at_css("p").traverse { |n| order << n.name }
puts order.inspect
puts em.matches?("p > em").inspect
puts em.matches?("div > em").inspect
puts doc.at_css("li").matches?("li:first-child").inspect
pairs = []
doc.at_css("li").each { |k, v| pairs << k + "=" + v }
puts pairs.inspect
puts doc.at_css("li").values.inspect
puts doc.at_css("li").value?("1").inspect
ul = doc.at_css("ul")
puts ul.elements.length.inspect
puts ul.first_element_child.text.inspect
puts ul.last_element_child.text.inspect
second = ul.first_element_child.next_element
puts second.text.inspect
puts second.previous_element.text.inspect
puts ul.last_element_child.next_element.inspect
puts ul.children.first.blank?.inspect
puts second.blank?.inspect
puts em.path.inspect
puts ul.children.first.path.inspect
puts em.line.inspect
n = doc.create_element("li")
n.content = "six"
ul << n
puts ul.elements.map { |e| e.text }.inspect
second.delete("class")
puts second.keys.inspect

x = Nokogiri::XML("<r>\n<a n=\"1\"><b/></a>\n<a/>\n</r>")
puts x.at_css("b").path.inspect
puts x.at_css("b").line.inspect
puts x.css("a").map { |e| e.path }.inspect
puts x.root.elements.map { |e| e.name }.inspect
