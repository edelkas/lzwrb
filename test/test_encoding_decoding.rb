require "minitest/autorun"
require "lzwrb"

# Encodes and then decodes a randomly generated 16KB sample with many different combinations of settings,
# ensuring that the result matches the original sample. Namely, every combination of min/max bit code size
# from 2 to 24 is used, both with and without clear/stop codes. The alphabet is chosen appropriately to be
# able to hold the data.
class EncodingDecodingTest < Minitest::Test
  def test_encoding_decoding
    (2..24).each{ |min_bits|
      (min_bits..24).each{ |max_bits|
        print("Testing #{min_bits}-#{max_bits} bits...".ljust(80, ' ') + "\r")
        max      = [1 << max_bits - 1, 256].min
        alphabet = (0 ... max).to_a.map(&:chr)
        data     = (16 * 1024).times.map{ |c| (max * rand).to_i.chr }.join.b

        [true, false].each{ |clear|
          [true, false].each{ |stop|
            lzw = LZWrb.new(min_bits: min_bits, max_bits: max_bits, clear: clear, stop: stop, alphabet: alphabet, verbosity: :minimal, binary: true)
            res = lzw.decode(lzw.encode(data))
            puts "Fail: #{min_bits}-#{max_bits}, #{clear}:#{stop}, #{alphabet.size}" if res != data
            assert res == data
          }
        }
      }
    }
  end
end
