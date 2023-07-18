require 'byebug'
require 'benchmark'

class LZW
  # Class default values (no NIL's here!)
  @@min_bits = 8     # Minimum code bit length
  @@max_bits = 12    # Maximum code bit length before rebuilding table
  @@lsb      = true  # Least significant bit first order
  @@clear    = true  # Use CLEAR and STOP codes (VALUES = 2 ** min_bits + {0, 1})

  # Print fixed-width LZW codes, for debugging purposes
  def self.print_codes(codes, width)
    puts "Hex Dec Binary"
    puts codes.unpack('b*')[0]
              .scan(/.{#{width}}/m)
              .map{ |c| c.reverse.to_i(2) }
              .map{ |c| "%03X %03d %0#{width}b" % [c, c, c] }
              .join("\n")
  end

  # TODO: Allow min_bits over 8 bits (hash keys will have to be packed)
  # TODO: Optimize by using Trie rather than standard Hash
  # TODO: Allow for custom alphabets (default is [0...2**min_bits], but we could also have a few standard ones [A..Z], [0..9], etc)
  # TODO: Implement MSB
  # TODO: Make code-less work
  # TODO: Add support for "early change"
  # TODO: Remember to clean code (delete $codes1, etc)
  def initialize(preset: nil, min_bits: nil, max_bits: nil, lsb: nil, clear: nil)
    # Parse params (preset and individual)
    params = parse_preset(preset)
    use_clear = find_arg(clear, params[:clear], @@clear)

    # Encoding params
    @min_bits = find_arg(min_bits, params[:min_bits], @@min_bits)
    @max_bits = find_arg(max_bits, params[:max_bits], @@max_bits)
    @lsb      = find_arg(lsb, params[:lsb], @@lsb)
    @clear    = use_clear ? (1 << @min_bits) + 0 : nil
    @stop     = use_clear ? (1 << @min_bits) + 1 : 1 << @min_bits
  end

  def compress(data)
    # Initialize output and table
    init(true)
    table_init

    # LZW-encode data
    buf = ''
    add_code(@clear) if !@clear.nil?
    data.each_char do |c|
      next_buf = buf + c
      if table_has(next_buf)
        buf = next_buf
      else
        add_code(@table[buf])
        table_add(next_buf)
        buf = c
      end
    end
    add_code(@table[buf])
    add_code(@stop)

    # Pack codes to binary string
    @buffer.pack('C*')
  end

  # Optimization? Unpack bits subsequently, rather than converting between strings and ints
  def decompress(data)
    # Setup
    init(false)
    table_init
    bits = data.unpack('b*')[0]
    len = bits.length

    # Parse data
    off = 0
    out = ''.b
    old_code = nil
    while off + @bits <= len
      # Parse code
      code = bits[off ... off + @bits].reverse.to_i(2)
      off += @bits
      $codes2 << code.to_s(2).rjust(@bits, '0')

      # Handle clear and stop codes, if present
      if code == @clear && @clear
        table_init
        old_code = nil
        next
      end
      break if code == @stop

      # Handle initial code
      if old_code.nil?
        out << @table[code]
        old_code = code
        if !@clear
          @key += 1
          @bits = @key.bit_length
        end
        next
      end

      # Update table
      if table_has(code)
        table_add(@table[old_code] + @table[code][0])
        out << @table[code]
      else
        table_add(@table[old_code] + @table[old_code][0])
        out << @table[-1]
      end

      # Prepare next iteration
      old_code = code
    end

    out
  end

  private

  # Return first non-nil argument
  def find_arg(*args)
    args.each{ |arg| arg.nil? ? next : (return arg) }
    nil
  end

  def parse_preset(preset)
    case preset
    when :gif
      {
        min_bits: 8,
        max_bits: 12,
        lsb:      true,
        clear:    true
      }
    else
      {}
    end
  end

  # Initialize buffers, needs to be called every time we execute a new
  # compression / decompression job
  def init(compress)
    @buffer = []         # Contains result of compression
    @boff = 0            # BIT offset of last buffer byte, for packing
    @compress = compress # Compressiong or decompression job
  end

  # Initializes the table, needs to be called at the start of each compression
  # / decompression job, as well as whenever the table gets full, which may
  # happen many times in a single job.
  #
  # During compression, the table is a hash. During decompression, the table
  # is an array, making the job faster.
  def table_init
    # Add symbols for all strings of length 1 (e.g. all 256 byte values)
    @key = (1 << @min_bits) - 1
    @table = @compress ? (0 .. @key).map{ |i| [i.chr, i] }.to_h : (0 .. @key).to_a.map(&:chr)

    # Increment key index if clear/stop symbols are being used
    if @clear
      @key += 1
      @table << '' if !@compress
    end
    if @stop
      @key += 1
      @table << '' if !@compress
    end
    @key += 1 if !@compress && @clear

    @bits = @key.bit_length
  end

  def table_has(val)
    @compress ? @table.include?(val) : @key > val
  end

  # Add new code to the table
  def table_add(val)
    # Add code
    @key += 1
    @compress ? (@table[val] = @key) : (@table << val)
    
    # Check variable width code constraints
    if @key == 1 << @bits
      if @bits == @max_bits
        add_code(@clear) if @compress && @clear
        table_init if @compress || !@clear
      else
        @bits += 1
      end
    end
  end

  def add_code2(code)
    bits = @bits

    while bits > 0
      # Pack bits in last byte if there's space, otherwise add new byte
      if @boff > 0
        @buffer[-1] |= code << @boff & 0xFF
      else
        @buffer << (code & 0xFF)
      end

      # If we didn't fill byte, packing is done, adjust offset and return
      if bits < 8 - @boff
        @boff += bits
        return
      end

      # Otherwise adjust code, bits left and offset, and do next iteration
      bits -= 8 - @boff
      code >>= 8 - @boff
      @boff = 0
    end
  end

  def add_code(code)
    bits = @bits
    $codes1 << code.to_s(2).rjust(@bits, '0')

    # Pack last byte
    if @boff > 0
      @buffer[-1] |= code << @boff & 0xFF
      if @bits < 8 - @boff
        @boff += @bits
        return
      end
      bits -= 8 - @boff
      code >>= 8 - @boff
      @boff = 0
    end

    # Add new bytes
    while bits > 0
      @buffer << (code & 0xFF)
      if bits < 8
        @boff = bits
        return
      end
      bits -= 8
      code >>= 8
    end
  end

end

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
  own = lzw.compress(File.binread(pixels))
  gif = deblockify(File.binread(gif)[0x32B..-2])
  puts own == gif
  gif.chars.each_with_index{ |c, i|
    if own[i] != c
      puts "Breaks at byte #{i}"
      break
    end
  }
end

# LZW-encode and decode a pixel array and see if they match
def decode_test(pixels: nil)
  lzw = LZW.new(preset: :gif, clear: false)
  file = File.binread(pixels)
  res = lzw.decompress(lzw.compress(file))
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
  puts Benchmark.measure{ 10.times{ lzw.compress(file) } }
end

def bench_decode(pixels: nil)
  lzw = LZW.new(preset: :gif)
  file = File.binread(pixels)
  cmp = lzw.compress(file)
  puts Benchmark.measure{ 10.times{ lzw.decompress(cmp) } }
end

$codes1 = []
$codes2 = []
lzw = LZW.new(preset: :gif)
#encode_test(pixels: 'gifenc/pixels', gif: 'gifenc/example.gif')
decode_test(pixels: 'gifenc/pixels')
#bench_encode(pixels: 'gifenc/pixels')