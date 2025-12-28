require 'keymap'

RSpec.describe Keymap do
  describe '.default' do
    subject(:mapping) { described_class.default }

    it 'returns a Hash' do
      expect(mapping).to be_a(Hash)
    end

    it 'has the expected size' do
      expect(mapping.size).to eq(32)
    end

    it 'includes expected key-to-action mappings' do
      expect(mapping).to include(
        'space'    => 'NEXT',
        'down'     => 'NEXT',
        'right'    => 'NEXT',
        'pagedown' => 'NEXT',
        'up'       => 'PREV',
        'left'     => 'PREV',
        'pageup'   => 'PREV',
        'SPACE'    => 'NEXTSEC',
        'DOWN'     => 'NEXTSEC',
        'RIGHT'    => 'NEXTSEC',
        'PAGEDOWN' => 'NEXTSEC',
        'UP'       => 'PREVSEC',
        'LEFT'     => 'PREVSEC',
        'PAGEUP'   => 'PREVSEC',
        'R'        => 'RELOAD',
        'r'        => 'REFRESH',
        'c'        => 'CONTENTS',
        't'        => 'CONTENTS',
        'h'        => 'HELP',
        '/'        => 'HELP',
        '?'        => 'HELP',
        'b'        => 'BLANK',
        '.'        => 'BLANK',
        'F'        => 'FOOTER',
        'f'        => 'FOLLOW',
        'n'        => 'NOTES',
        'esc'      => 'CLEAR',
        'p'        => 'PAUSE',
        'P'        => 'PRESHOW',
        'x'        => 'EXECUTE',
        'f5'       => 'EXECUTE',
        'd'        => 'DEBUG'
      )
    end

    it 'contains only valid action names' do
      valid_actions = %w[
        DEBUG NEXT PREV NEXTSEC PREVSEC RELOAD REFRESH CONTENTS HELP BLANK
        FOOTER FOLLOW NOTES CLEAR PAUSE PRESHOW EXECUTE
      ]
      expect(mapping.values.uniq - valid_actions).to be_empty
    end
  end

  describe '.keycodeDictionary' do
    subject(:mapping) { described_class.keycodeDictionary }

    it 'returns a Hash' do
      expect(mapping).to be_a(Hash)
    end

    it 'has the expected size' do
      expect(mapping.size).to eq(112)
    end

    it 'includes representative keycode-to-key mappings' do
      expect(mapping).to include(
        '8'    => 'backspace',
        '9'    => 'tab',
        '12'   => 'num',
        '13'   => 'enter',
        '16'   => 'shift',
        '17'   => 'ctrl',
        '18'   => 'alt',
        '19'   => 'pause',
        '20'   => 'caps',
        '27'   => 'esc',
        '32'   => 'space',
        '33'   => 'pageup',
        '34'   => 'pagedown',
        '35'   => 'end',
        '36'   => 'home',
        '37'   => 'left',
        '38'   => 'up',
        '39'   => 'right',
        '40'   => 'down',
        '48'   => '0',
        '57'   => '9',
        '65'   => 'a',
        '90'   => 'z',
        '91'   => 'cmd',
        '112'  => 'f1',
        '123'  => 'f12',
        '96'   => 'num_0',
        '105'  => 'num_9',
        '111'  => 'num_divide',
        '173'  => '-',
        '188'  => ',',
        '190'  => '.',
        '191'  => '/',
        '192'  => '`',
        '219'  => '[',
        '220'  => '\\',
        '221'  => ']',
        '222'  => "'",
        '224'  => 'cmd',
        '225'  => 'alt'
      )
    end

    it 'uses string keys and values' do
      expect(mapping.keys).to all(be_a(String))
      expect(mapping.values).to all(be_a(String))
    end
  end

  describe '.shiftedKeyDictionary' do
    subject(:mapping) { described_class.shiftedKeyDictionary }

    it 'returns a Hash' do
      expect(mapping).to be_a(Hash)
    end

    it 'has the expected size' do
      expect(mapping.size).to eq(28)
    end

    it 'includes expected unshifted-to-shifted mappings for digits and punctuation' do
      expect(mapping).to include(
        '0' => ')',
        '1' => '!',
        '2' => '@',
        '3' => '#',
        '4' => '$',
        '5' => '%',
        '6' => '^',
        '7' => '&',
        '8' => '*',
        '9' => '(',
        '/' => '?',
        '.' => '>',
        ',' => '<',
        "'" => '"',
        ';' => ':',
        '[' => '{',
        ']' => '}',
        '\\' => '|',
        '`' => '~',
        '=' => '+',
        '-' => '_'
      )
    end

    it 'includes expected shifted navigation keys' do
      expect(mapping).to include(
        'space'    => 'SPACE',
        'down'     => 'DOWN',
        'right'    => 'RIGHT',
        'pagedown' => 'PAGEDOWN',
        'up'       => 'UP',
        'left'     => 'LEFT',
        'pageup'   => 'PAGEUP'
      )
    end
  end
end
