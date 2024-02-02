require "minitest/autorun"
require "lzwrb"

# Encodes the raw pixel data of a GIF and compares it with the encoded data in the GIF itself, to ensure the GIF
# specification is being honored.
class GifTest < Minitest::Test
  # Store data in 256-byte blocks used by GIF
  def blockify(data)
    return "\x00".b if data.size == 0
    ff = "\xFF".b.freeze
    off = 0
    out = "".b
    len = data.length
    for _ in (0 ... len / 255)
      out << ff << data[off ... off + 255]
      off += 255
    end
    out << (len - off).chr << data[off..-1] if off < len
    out << "\x00".b
    out
  rescue
    "\x00".b
  end
  
  # Recover data from 256-byte blocks used by GIF
  def deblockify(data)
    out = ""
    size = data[0].ord
    off = 0
    while size != 0
      out << data[off + 1 .. off + size]
      off += size + 1
      size = data[off].ord
    end
    out
  rescue
    ''.b
  end

  def test_gif
    lzw = LZWrb.new(preset: LZWrb::PRESET_GIF, verbosity: :minimal)
    own = lzw.encode(File.binread('test/pixel_data'))
    gif = deblockify(File.binread('test/sample.gif')[0x32B..-2])
    assert own == gif
  end
end
