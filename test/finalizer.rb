# The documents, observed. Not a conformance test -- the gem has no count
# to compare -- so it has no `_test` suffix and the oracle leaves it alone;
# `spin test` runs it.
#
# Every parse makes an owner that only the GC gives back, freeing the
# document and every node that was unlinked from it (sp_nokogiri.c). The
# loop does Markdowner's edits -- create_element, replace (which unlinks),
# renaming, attributes -- three thousand times, and keeps handles to
# detached nodes past the edit. A leak would leave the documents counted;
# a node freed too early would crash.
require "nokogiri"

made = 0
bytes = 0
kept = []
3000.times do |i|
  doc = Nokogiri::HTML("<h1>t#{i}</h1><p>x <img src=\"/#{i}.png\" alt=\"a\"> <a href=\"/\">l</a></p>")
  made += 1
  doc.css("h1").each { |h| h.name = "strong" }
  img = doc.at_css("img")
  link = doc.create_element("a")
  link["href"] = img["src"]
  link.content = img["alt"]
  img.replace(link)
  kept << img if i % 100 == 0
  doc.css("a").each { |a| a[:rel] = "ugc" }
  bytes += doc.at_css("body").inner_html.length
end
# XML documents too, with the namespace definitions remove_namespaces!
# and a reparent's relinking take off their elements (kept with the owner
# and freed with the document), and parse errors.
xml_made = 0
3000.times do |i|
  doc = Nokogiri::XML("<f xmlns=\"u\" xmlns:m=\"mm\"><e><m:t n=\"#{i}\"/></e><bad></f>")
  xml_made += 1
  e = doc.create_element("e")
  e.add_child(doc.create_element("m:t"))
  doc.root.add_child(e)
  kept << e if i % 100 == 0
  doc.remove_namespaces! if i.even?
  bytes += doc.to_xml.length + doc.errors.length
end
made += xml_made
puts "kept detached: #{kept.length}"
kept = []
GC.start
live = NokogiriExt.sp_noko_live_documents
puts "made: #{made}"
puts "rendered: #{bytes > 0}"
puts "released after GC: #{live < made / 2}"
