# HTML5 over the same 3404 documents as markdowner_test.rb (the
# commonmarker gem's renders of the CommonMark and GFM spec examples and of
# lobsters' fake data, safe and `unsafe`, so real tag soup): each parsed as
# a document (the body's inner_html, and how many errors gumbo reports) and
# as a fragment (printed when it differs from the body), then given
# Markdowner's edits — headings renamed, images replaced by links, rel on
# every link — through HTML5. Every line is the gem's answer.
require "nokogiri"

def present(v)
  !v.nil? && !v.strip.empty?
end

def edit(ng)
  ng.css("h1, h2, h3, h4, h5, h6").each { |h| h.name = "strong" }
  ng.css("img").each do |img|
    link = ng.document.create_element("a")
    link["href"] = img["src"].to_s
    link.content = [img["title"].to_s, img["alt"].to_s, link["href"]].find { |v| present(v) }
    img.replace link
  end
  ng.css("a").each { |a| a[:rel] = "ugc" }
  nil
end

docs = File.read(File.join(File.dirname(__FILE__), "corpus", "markdown_html.txt")).split("\x1e\n", -1)
docs.each_with_index do |html, i|
  doc = Nokogiri::HTML5(html, max_errors: 100)
  body = doc.at_css("body")
  inner = body ? body.inner_html : ""
  puts "#{i} #{doc.errors.length} #{inner.inspect}"
  frag = Nokogiri::HTML5.fragment(html).to_html
  puts "#{i} fragment #{frag.inspect}" unless frag == inner
  edit(doc)
  edited = body ? body.inner_html : ""
  puts "#{i} edited #{edited.inspect}" unless edited == inner
end
