# Nokogiri::HTML.fragment and HTML4::Document#meta_encoding — campfire's
# turbo-stream test helper hands a fragment to assert_select (which reads
# it through to_s), and its Opengraph::Document asks a page whether it
# declared an encoding. Every line is the gem's answer.
require "nokogiri"

[
  "<turbo-stream action=\"append\" target=\"messages\"><template><p>hi</p></template></turbo-stream>",
  "<p>one</p> text <b>two</b>",
  "  <body><p>in body</p></body>",
  "",
  "plain",
  "<li>x</li><li>y</li>",
].each do |tags|
  f = Nokogiri::HTML.fragment(tags)
  puts f.to_s.inspect
  puts f.children.length.inspect
  puts f.css("p").map { |n| n.text }.inspect
end

[
  "<html><head><meta charset=\"utf-8\"></head><body></body></html>",
  "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=ISO-8859-1\"></head></html>",
  "<html><head><meta http-equiv=\"content-type\" content=\"text/html\"></head></html>",
  "<p>no meta</p>",
].each do |html|
  puts Nokogiri::HTML(html).meta_encoding.inspect
end
