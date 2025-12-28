RSpec.describe Showoff::Compiler::Glossary do
  content = <<-EOF
<h1>This is a simple HTML slide with glossary entries</h1>
<p>This will have <a href="glossary://term-with-no-spaces" title="The definition of the term.">a phrase</a> in the paragraph.</p>
<p class="callout glossary">By hand, yo!|by-hand: I made this one by hand.</p>
<p>This <a href="glossary://name/term-with-no-spaces" title="The definition of the term.">entry</a> is attached to a named glossary.</p>
<p class="callout glossary name">By hand, yo!|by-hand: I made this one by hand.</p>
EOF

  it "generates glossary entries on a slide" do
    doc = Nokogiri::HTML::DocumentFragment.parse(content)

    # This call mutates the passed in object
    Showoff::Compiler::Glossary.render!(doc)

    callouts = doc.search('.callout.glossary').select {|n| n.ancestors.size == 1}
    links    = doc.search('a').select {|n| n.ancestors.size == 2}

    expect(doc).to be_a(Nokogiri::HTML::DocumentFragment)
    expect(doc.search('.callout.glossary').length).to eq(6)
    expect(callouts.length).to eq(2)
    expect(callouts.first.classes).to eq(["callout", "glossary"])
    expect(callouts.first.element_children.size).to eq(1)
    expect(callouts.first.element_children.first[:href]).to eq('glossary://by-hand')

    expect(callouts.last.classes).to eq(["callout", "glossary", "name"])
    expect(callouts.last.element_children.size).to eq(1)
    expect(callouts.last.element_children.first[:href]).to eq('glossary://name/by-hand')

    expect(links.length).to eq(4)
    expect(links.select {|link| link[:href].start_with? 'glossary://'}.size).to eq(4)
    expect(links.select {|link| link.classes.include? 'term'}.size).to eq(2)
    expect(links.select {|link| link.classes.include? 'label'}.size).to eq(2)
  end

  it "generates glossary entries in the presenter notes section of a slide" do
    doc = Nokogiri::HTML::DocumentFragment.parse(content)

    # This call mutates the passed in object
    Showoff::Compiler::Glossary.render!(doc)

    expect(doc).to be_a(Nokogiri::HTML::DocumentFragment)
    expect(doc.search('.notes-section.notes').length).to eq(1)
    expect(doc.search('.notes-section.notes > .callout.glossary').length).to eq(2)
    expect(doc.search('.notes-section.handouts > .callout.glossary').length).to eq(2)
  end

  it "generates glossary entries in the handout notes section of a slide" do
    doc = Nokogiri::HTML::DocumentFragment.parse(content)

    # This call mutates the passed in object
    Showoff::Compiler::Glossary.render!(doc)

    expect(doc).to be_a(Nokogiri::HTML::DocumentFragment)
    expect(doc.search('.notes-section.handouts').length).to eq(1)
    expect(doc.search('.notes-section.handouts > .callout.glossary').length).to eq(2)
  end

  it "generates a glossary page" do
    html = File.read(File.join(fixtures, 'glossary_toc', 'content.html'))
    doc  = Nokogiri::HTML::DocumentFragment.parse(html)

    Showoff::Compiler::Glossary.generatePage!(doc)

    expect(doc.search('.slide.glossary:not(.name)').size).to eq(1)
    expect(doc.search('.slide.glossary:not(.name) li a').size).to eq(4)
    expect(doc.search('.slide.glossary:not(.name) li a')[0][:id]).to eq('content:3+by-hand')
    expect(doc.search('.slide.glossary:not(.name) li a')[1][:href]).to eq('#content:2')
    expect(doc.search('.slide.glossary:not(.name) li a')[2][:id]).to eq('content:3+term-with-no-spaces')
    expect(doc.search('.slide.glossary:not(.name) li a')[3][:href]).to eq('#content:2')

    expect(doc.search('.slide.glossary.name').size).to eq(1)
    expect(doc.search('.slide.glossary.name li a').size).to eq(4)
    expect(doc.search('.slide.glossary.name li a')[0][:id]).to eq('content:4+by-hand')
    expect(doc.search('.slide.glossary.name li a')[1][:href]).to eq('#content:2')
    expect(doc.search('.slide.glossary.name li a')[2][:id]).to eq('content:4+term-with-no-spaces')
    expect(doc.search('.slide.glossary.name li a')[3][:href]).to eq('#content:2')
  end

  # New tests for empty glossary
  it "handles an empty glossary page with no entries" do
    empty_glossary_html = <<-EOF
<div id="content1" class="slide glossary" style="" data-section="." data-title="content" data-transition="none">
  <div class="content glossary" ref="content:1">
    <h1 class="section_title">.</h1>
    <h1>Empty Glossary</h1>
    <p>This glossary has no entries.</p>
  </div>
  <canvas class="annotations"></canvas>
</div>
EOF
    doc = Nokogiri::HTML::DocumentFragment.parse(empty_glossary_html)

    Showoff::Compiler::Glossary.generatePage!(doc)

    # Verify the glossary page exists but has no entries
    expect(doc.search('.slide.glossary').size).to eq(1)
    expect(doc.search('.slide.glossary .content').size).to eq(1)
    expect(doc.search('.slide.glossary .terms').size).to eq(1)
    expect(doc.search('.slide.glossary .terms li').size).to eq(0)
  end

  # New tests for duplicate entries
  it "de-duplicates glossary entries with the same term" do
    duplicate_entries_html = <<-EOF
<div id="content1" class="slide glossary" style="" data-section="." data-title="content" data-transition="none">
  <div class="content glossary" ref="content:1">
    <h1 class="section_title">.</h1>
    <h1>Glossary with Duplicates</h1>
  </div>
  <canvas class="annotations"></canvas>
</div>
<div id="content2" class="slide" style="" data-section="." data-title="content" data-transition="none">
  <div class="content" ref="content:2">
    <h1>Slide with duplicate glossary entries</h1>
    <p class="callout glossary" data-term="Duplicate Term" data-target="duplicate" data-text="First definition">
      <a class="processed label" href="glossary://duplicate">Duplicate Term</a>First definition
    </p>
    <p class="callout glossary" data-term="Duplicate Term" data-target="duplicate" data-text="Second definition">
      <a class="processed label" href="glossary://duplicate">Duplicate Term</a>Second definition
    </p>
  </div>
</div>
EOF
    doc = Nokogiri::HTML::DocumentFragment.parse(duplicate_entries_html)

    Showoff::Compiler::Glossary.generatePage!(doc)

    # Verify only one entry exists for the duplicate term
    expect(doc.search('.slide.glossary .terms li').size).to eq(1)
    expect(doc.search('.slide.glossary .terms li a.label').first.content).to eq('Duplicate Term')
  end

  # New tests for missing href attributes
  it "skips links with missing href attributes during page generation" do
    missing_href_html = <<-EOF
<div id="content1" class="slide glossary" style="" data-section="." data-title="content" data-transition="none">
  <div class="content glossary" ref="content:1">
    <h1 class="section_title">.</h1>
    <h1>Glossary Page</h1>
  </div>
  <canvas class="annotations"></canvas>
</div>
<div id="content2" class="slide" style="" data-section="." data-title="content" data-transition="none">
  <div class="content" ref="content:2">
    <h1>Slide with links</h1>
    <p><a class="term" title="Valid link">Valid link with no href</a></p>
    <p><a href="glossary://valid-term" class="term" title="Valid link">Valid glossary link</a></p>
    <p><a href="https://example.com" class="term" title="Non-glossary link">Non-glossary link</a></p>
  </div>
</div>
EOF
    doc = Nokogiri::HTML::DocumentFragment.parse(missing_href_html)

    # Count links before processing
    links_before = doc.search('a').size

    Showoff::Compiler::Glossary.generatePage!(doc)

    # Verify links without href are skipped and don't cause errors
    expect(doc.search('.slide.glossary .terms li').size).to eq(0)
    expect(doc.search('a').size).to eq(links_before) # No links should be removed
  end

  # Test for glossary entries from callouts
  it "generates glossary from callouts that match the glossary name" do
    callout_html = <<-EOF
<div id="content1" class="slide glossary" style="" data-section="." data-title="content" data-transition="none">
  <div class="content glossary" ref="content:1">
    <h1 class="section_title">.</h1>
    <h1>Glossary Page</h1>
  </div>
  <canvas class="annotations"></canvas>
</div>
<div id="content2" class="slide" style="" data-section="." data-title="content" data-transition="none">
  <div class="content" ref="content:2">
    <h1>Slide with callouts</h1>
    <p class="callout glossary" data-term="Term One" data-target="complete" data-text="First entry">
      <a class="processed label" href="glossary://complete">Term One</a>First entry
    </p>
    <p class="callout glossary" data-term="Term Two" data-target="complete" data-text="Second entry">
      <a class="processed label" href="glossary://complete">Term Two</a>Second entry
    </p>
  </div>
</div>
EOF
    doc = Nokogiri::HTML::DocumentFragment.parse(callout_html)

    Showoff::Compiler::Glossary.generatePage!(doc)

    # The callouts have no matching glossary name (nil vs nil should match)
    # so they should be included in the default glossary
    terms = doc.search('.slide.glossary .terms li')
    expect(terms.size).to eq(2)
  end

  # Test for link rewriting with callouts
  it "includes callout terms in glossary" do
    link_rewriting_html = <<-EOF
<div id="content1" class="slide glossary" style="" data-section="." data-title="content" data-transition="none">
  <div class="content glossary" ref="content:1">
    <h1 class="section_title">.</h1>
    <h1>Glossary Page</h1>
  </div>
  <canvas class="annotations"></canvas>
</div>
<div id="content2" class="slide" style="" data-section="." data-title="content" data-transition="none">
  <div class="content" ref="content:2">
    <h1>Slide with links</h1>
    <p class="callout glossary" data-term="term1" data-target="term1" data-text="Term one definition">
      <a class="processed label" href="glossary://term1">term1</a>Term one definition
    </p>
  </div>
</div>
EOF
    doc = Nokogiri::HTML::DocumentFragment.parse(link_rewriting_html)

    Showoff::Compiler::Glossary.generatePage!(doc)

    # Verify the glossary has terms
    terms = doc.search('.slide.glossary .terms li')
    expect(terms.size).to eq(1)
  end
end