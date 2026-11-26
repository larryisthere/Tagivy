# Contributing to Tagivy

Thank you for helping improve Tagivy.

## Before opening a pull request

1. Describe the user-facing problem and the expected result.
2. Keep changes focused and preserve read-only access to original files.
3. Express new rules as code: a test for behavior, or a check in `script/check_invariants.rb` for project-wide rules. Update the changelog when user-visible behavior changes.
4. Run `ruby script/check_invariants.rb` and the test suite successfully.
5. Avoid including personal file paths, filenames, tags, bookmarks, library databases, signing credentials, or generated release artifacts.

Automated checks validate only their stated assertions. Product logic, interaction, and UI changes still require explicit user acceptance before release.

For security issues, follow [SECURITY.md](SECURITY.md) and use a private GitHub Security Advisory.
