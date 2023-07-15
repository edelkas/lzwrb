require 'byebug'

class LZW
  attr_accessor :debug

  # Class default values (no NIL's here!)
  @@min_bits = 8     # Minimum code bit length
  @@max_bits = 12    # Maximum code bit length before rebuilding dictionary
  @@lsb      = true  # Least significant bit first order
  @@codes    = true  # Use CLEAR and STOP codes (VALUES = 2 ** min_bits + {0, 1})

  # PRint fixed-width LZW codes, for debugging purposes
  def self.print_codes(codes, width)
    puts "Hex Dec Binary"
    puts codes.unpack('b*')[0]
              .scan(/.{#{width}}/m)
              .map{ |c| c.reverse.to_i(2) }
              .map{ |c| "%03X %03d %09b" % [c, c, c] }
              .join("\n")
  end

  # TODO: Allow min_bits over 8 bits (dict keys will have to be packed)
  # TODO: Optimize by using Trie rather than standard Hash
  def initialize(preset: nil, min_bits: nil, max_bits: nil, lsb: nil, codes: nil, debug: 0)
    # Parse params (preset and individual)
    params = parse_preset(preset)
    use_codes = find_arg(codes, params[:codes], @@codes)

    # Encoding params
    @min_bits = find_arg(min_bits, params[:min_bits], @@min_bits)
    @max_bits = find_arg(max_bits, params[:max_bits], @@max_bits)
    @lsb      = find_arg(lsb, params[:lsb], @@lsb)
    @clear    = use_codes ? 1 << @min_bits : nil
    @stop     = use_codes ? @clear + 1     : nil

    # Config params
    @debug = debug
  end

  def compress(data)
    # Initialize output and dictionary
    init
    dict_init

    # LZW-encode data
    buf = ''
    add_code(@clear) if !@clear.nil?
    data.each_char do |c|
      next_buf = buf + c
      if dict_has(next_buf)
        buf = next_buf
      else
        add_code(@dict[buf])
        dict_add(next_buf)
        buf = c
      end
    end
    add_code(@dict[buf])
    add_code(@stop) if !@stop.nil?

    # Pack codes to binary string
    @buffer.pack('C*')
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
        codes:    true
      }
    else
      {}
    end
  end

  # Initialize buffers, needs to be called every time we execute a new
  # compression / decompression job
  def init
    @buffer = [] # Contains result of compression
    @boff = 0    # BIT offset of last buffer byte, for packing
  end

  # Initializes the dictionary, needs to be called at the start of each compression
  # / decompression job, as well as whenever the dictionary gets full, which may
  # happen many times in a single job
  def dict_init
    # Add symbols for all strings of length 1 (e.g. all 256 byte values)
    @key = (1 << @min_bits) - 1
    @dict = (0 .. @key).map{ |i| [i.chr, i] }.to_h

    # Increment key index if clear/stop symbols are being used
    @key += 1 if !@clear.nil?
    @key += 1 if !@stop.nil?
    @bits = @key.bit_length
  end

  def dict_has(str)
    @dict.include?(str)
  end

  # Add new code to the dictionary
  def dict_add(str)
    # Add code
    @key += 1
    @dict[str] = @key
    puts("<- Dict  %0#{(@bits.to_f / 4).ceil}X = %s" % [@key, str.bytes.map{ |b| "%02X" % b }.join(' ')]) if debug >= 1
    
    # Check variable width code constraints
    if @key == 1 << @bits
      if @bits == @max_bits
        add_code(@clear) if !@clear.nil?
        dict_init
        puts "Reset dictionary"
      else
        @bits += 1
        puts "Increased code size to #{@bits}"
      end
    end
  end

  # TODO: Implement MSB method
  def add_code2(code)
    puts("-> Added %0#{(@bits.to_f / 4).ceil}X" % code) if debug >= 1
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
    puts if debug >= 2
    puts("-> Added %0#{(@bits.to_f / 4).ceil}X" % code) if debug >= 1
    puts("Code: %0#{@bits}b" % code) if debug >= 2
    bits = @bits

    # Pack last byte
    if @boff > 0
      puts("Boff: %d" % @boff) if debug >= 2
      puts("Bits: %d" % bits) if debug >= 2
      puts("Pack:  %08b" % [code << @boff & 0xFF]) if debug >= 2
      puts("Last:  %08b" % @buffer[-1]) if debug >= 2
      @buffer[-1] |= code << @boff & 0xFF
      puts("New:   %08b" % @buffer[-1]) if debug >= 2
      if @bits < 8 - @boff
        @boff += @bits
        puts if debug >= 2
        return
      end
      bits -= 8 - @boff
      code >>= 8 - @boff
      @boff = 0
    end

    # Add new bytes
    while bits > 0
      puts("Boff: %d" % @boff) if debug >= 2
      puts("Bits: %d" % bits) if debug >= 2
      puts("Pack:  %08b" % [code & 0xFF]) if debug >= 2
      @buffer << (code & 0xFF)
      if bits < 8
        @boff = bits
        puts if debug >= 2
        return
      end
      bits -= 8
      code >>= 8
    end

    puts if debug >= 2
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
def test(gif: nil, pixels: nil)
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

lzw = LZW.new(preset: :gif, debug: 0)
test(pixels: '../gifenc/pixels', gif: '../gifenc/example.gif')