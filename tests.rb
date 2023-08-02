require 'byebug'
require 'benchmark'

require_relative 'lzw'

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

# LZW-encode a pixel array read from a file, and compare with a properly generated
# GIF to see if they match.
def encode_test(gif: nil, pixels: nil)
  lzw = LZW.new(preset: :gif)
  own = lzw.encode(File.binread(pixels))
  gif = deblockify(File.binread(gif)[0x32B..-2])
  cmp = own == gif
  puts cmp
  if !cmp
    gif.chars.each_with_index{ |c, i|
      if own[i] != c
        puts "Breaks at byte #{i}"
        break
      end
    }
  end
end

def test(data, alphabet, min_bits, max_bits)
  [true, false].each{ |clear|
    [true, false].each{ |stop|
      $codes1 = []
      $codes2 = []
      $table1 = []
      $table2 = []
      $init1 = []
      $init2 = []
      
      lzw = LZW.new(min_bits: min_bits, max_bits: max_bits, clear: clear, stop: stop, alphabet: alphabet, verbosity: :minimal)
      t = Time.now
      cmp = lzw.encode(data)
      t1 = Time.now - t
      t = Time.now
      res = lzw.decode(cmp)
      t2 = Time.now - t
      $times[min_bits][max_bits] << [t1, t2]
      puts "Fail: #{min_bits}-#{max_bits}, #{clear}:#{stop}, #{alphabet.size}" if res != data
    }
  }
end

def tests
  (2..24).each{ |min_bits|
    $times[min_bits] = {}
    (2..24).each{ |max_bits|
      $times[min_bits][max_bits] = []
      print("Testing #{min_bits}-#{max_bits} bits...".ljust(80, ' ') + "\r")
      max = [1 << max_bits - 1, 256].min
      alphabet = (0 ... max).to_a.map(&:chr)
      data = (16 * 1024).times.map{ |c| (max * rand).to_i.chr }.join
      test(data, alphabet, min_bits, max_bits)
    }
  }
end

# LZW-encode and decode a pixel array and see if they match
def decode_test
  lzw = LZW.new(preset: :gif, safe: false, alphabet: (0 ... 256).to_a.map(&:chr))
  file = (256 * 1024).times.map{ |c| (2 * rand).to_i.chr }.join
  res = lzw.decode(lzw.encode(file))
  cmp = file == res
  puts cmp
  if !cmp
    file.chars.each_with_index{ |c, i|
      if res[i] != c
        puts "Breaks at byte #{i}"
        break
      end
    }
    byebug
  end
end

def bench_encode(pixels: nil)
  lzw = LZW.new(preset: :gif)
  file = File.binread(pixels)
  puts Benchmark.measure{ 10.times{ lzw.encode(file) } }
end

def bench_decode(pixels: nil)
  lzw = LZW.new(preset: :gif)
  file = File.binread(pixels)
  cmp = lzw.encode(file)
  puts Benchmark.measure{ 10.times{ lzw.decode(cmp) } }
end

$codes1 = []
$codes2 = []
$table1 = []
$table2 = []
$init1 = []
$init2 = []
$times = {}
$ratios = {}
#lzw = LZW.new(min_bits: 5, max_bits: 8, clear: false, stop: false, alphabet: LZW::LATIN_UPPER.unshift('#'))
#lzw.encode('TOBEORNOTTOBEORTOBEORNOT#')
#encode_test(pixels: 'gifenc/pixels', gif: 'gifenc/example.gif')
decode_test
#bench_encode(pixels: 'gifenc/pixels')
#bench_decode(pixels: 'gifenc/pixels')
#tests