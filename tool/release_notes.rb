# Release notes from CHANGELOG.md. A release shows its whole version section; a beta shows only the
# entries added since the previous beta of the same version, so testers see what is new to them.
require "set"

module ReleaseNotes
  module_function

  # The body of `## [version]` in a changelog, without its heading, or nil.
  def section(changelog, version)
    lines = changelog.to_s.lines
    heading = /^## \[#{Regexp.escape(version)}\](?:\s+-.*)?\s*$/
    start = lines.index { |line| line.match?(heading) } or return nil
    finish = lines.each_index.find { |index| index > start && lines[index].start_with?("## [") } || lines.length
    lines[(start + 1)...finish].join.strip
  end

  # Entries of `current` that `previous` does not have, kept under their `###` headings.
  def added_since(previous, current)
    known = entries(previous).map { |_, entry| entry }.to_set
    groups = Hash.new { |hash, key| hash[key] = [] }
    entries(current).each { |heading, entry| groups[heading] << entry unless known.include?(entry) }
    groups.map { |heading, items| [heading, items.map { |item| "- #{item}" }.join("\n")].compact.join("\n\n") }.join("\n\n")
  end

  def entries(section)
    heading = nil
    section.to_s.lines.filter_map do |line|
      if line.start_with?("### ")
        heading = line.strip
        nil
      elsif line.start_with?("- ")
        [heading, line.delete_prefix("- ").strip]
      end
    end
  end
end
