# lobsters' Markdowner post-processing, verbatim in what it asks of
# Nokogiri, over 2500+ HTML documents: the commonmarker gem's own renders
# of the CommonMark and GFM spec examples and lobsters' fake data, safe and
# `unsafe` (raw HTML passed through, which gives the parser real tag soup).
# Headings become <strong>, links get rel=ugc, images become links carrying
# their title/alt/src, and the answer is the body's inner_html. Every line
# is the gem's answer (`sh oracle/run.sh`); `spin test` holds the port to it.
require "nokogiri"

def present(v)
  !v.nil? && !v.strip.empty?
end

def post_process(html, allow_images)
  ng = Nokogiri::HTML(html)
  ng.css("h1, h2, h3, h4, h5, h6").each do |h|
    h.name = "strong"
  end
  unless allow_images
    ng.css("img").each do |img|
      link = ng.create_element("a")
      link["href"], title, alt = img.attributes.values_at("src", "title", "alt").map { |a| a.to_s }
      link.content = [title, alt, link["href"]].find { |v| present(v) }
      img.replace link
    end
  end
  ng.css("a").each do |h|
    h[:rel] = "ugc"
  end
  body = ng.at_css("body")
  body ? body.inner_html : ""
end

docs = File.read(File.join(File.dirname(__FILE__), "corpus", "markdown_html.txt")).split("\x1e\n", -1)
docs.each_with_index do |html, i|
  puts "#{i} #{post_process(html, i.odd?).inspect}"
end
