require "rexml/document"
require "time"

# Builds the Sparkle appcast the app reads (SUFeedURL in Config/Info.plist).
# Stable releases have no channel; betas are on the "beta" channel, which the app
# only accepts when the user turns on beta versions.
module Appcast
  SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle".freeze
  BETA_CHANNEL = "beta".freeze
  MAX_ITEMS = 30

  Item = Struct.new(
    :title, :build, :display_version, :beta, :minimum_system_version,
    :download_url, :length, :ed_signature, :release_notes_url, :published_at,
    keyword_init: true
  )

  module_function

  # Returns the appcast XML with `item` added, replacing any earlier entry for the same build.
  def with_item(existing_xml, item, title:)
    document = existing_xml.to_s.strip.empty? ? empty_document(title) : REXML::Document.new(existing_xml)
    channel = document.root.elements["channel"] or raise ArgumentError, "appcast has no channel"
    channel.elements.to_a("item").each do |element|
      channel.delete_element(element) if element.elements["sparkle:version"]&.text.to_s == item.build.to_s
    end

    items = channel.elements.to_a("item")
    items.each { |element| channel.delete_element(element) }
    items.unshift(item_element(item))
    items.sort_by! { |element| -Integer(element.elements["sparkle:version"].text) }
    items.first(MAX_ITEMS).each { |element| channel.add_element(element) }

    output = +""
    formatter = REXML::Formatters::Pretty.new(2)
    formatter.compact = true
    formatter.width = 10_000
    formatter.write(document, output)
    "#{output}\n"
  end

  def empty_document(title)
    document = REXML::Document.new
    document << REXML::XMLDecl.new("1.0", "utf-8")
    rss = document.add_element("rss", "version" => "2.0", "xmlns:sparkle" => SPARKLE_NAMESPACE)
    channel = rss.add_element("channel")
    channel.add_element("title").text = title
    document
  end

  def item_element(item)
    element = REXML::Element.new("item")
    element.add_element("title").text = item.title
    element.add_element("pubDate").text = item.published_at.utc.rfc2822
    element.add_element("sparkle:version").text = item.build.to_s
    element.add_element("sparkle:shortVersionString").text = item.display_version
    element.add_element("sparkle:channel").text = BETA_CHANNEL if item.beta
    element.add_element("sparkle:minimumSystemVersion").text = item.minimum_system_version
    element.add_element("sparkle:fullReleaseNotesLink").text = item.release_notes_url
    element.add_element(
      "enclosure",
      "url" => item.download_url,
      "length" => item.length.to_s,
      "type" => "application/octet-stream",
      "sparkle:edSignature" => item.ed_signature
    )
    element
  end
end
