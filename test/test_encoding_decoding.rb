require "minitest/autorun"
require "lzwrb"

# Encodes and then decodes a randomly generated 16KB sample with many different
# settings combinations, ensuring that the result matches the original sample.
# Namely, every combination of min/max bit code size from 2 to 20 is used, both
# with and without clear/stop codes, and both binary and textual mode. The
# alphabet is chosen appropriately to be able to hold the data.
#
# WARNING: This test takes several minutes.
class EncodingDecodingTest < Minitest::Test
  MIN_BITS  = 2
  MAX_BITS  = 20
  DATA_SIZE = 16 * 1024

  def test_encoding_decoding
    (MIN_BITS..MAX_BITS).each{ |min_bits|
      (min_bits..MAX_BITS).each{ |max_bits|
        print("Testing #{min_bits}-#{max_bits} bits...".ljust(80, ' ') + "\r")
        max      = [1 << max_bits - 1, 256].min
        alphabet = (0 ... max).to_a.map(&:chr)
        data     = DATA_SIZE.times.map{ |c| (max * rand).to_i.chr }.join.b

        [true, false].each{ |clear|
          [true, false].each{ |stop|
            [true, false].each{ |binary|
              lzw = LZWrb.new(
                min_bits:  min_bits,
                max_bits:  max_bits,
                clear:     clear,
                stop:      stop,
                alphabet:  alphabet,
                binary:    binary,
                verbosity: :minimal,
                safe: true
              )
              res = lzw.decode(lzw.encode(data)).b == data
              puts "FAIL: bits: #{min_bits}-#{max_bits}, codes: #{clear}-#{stop}, binary: #{binary}, alphabet size: #{alphabet.size}" if !res
              assert res
            }
          }
        }
      }
    }
  end
end
