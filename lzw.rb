require 'byebug'
require 'benchmark'

class LZW

  # Default alphabets
  DEC         = (0...10).to_a
  HEX_UPPER   = (0...16).to_a.map{ |n| n.to_s(16).upcase }
  HEX_LOWER   = (0...16).to_a.map{ |n| n.to_s(16).downcase }
  LATIN_UPPER = ('A'..'Z').to_a
  LATIN_LOWER = ('a'..'z').to_a
  ALPHA_UPPER = LATIN_UPPER + DEC
  ALPHA_LOWER = LATIN_LOWER + DEC
  ALPHA       = LATIN_UPPER + LATIN_LOWER + DEC
  PRINTABLE   = (32...127).to_a.map(&:chr)
  ASCII       = (0...128).to_a.map(&:chr)
  BINARY      = (0...256).to_a.map(&:chr)

  # Verbosity of the encoder/decoder
  VERBOSITY = {
    silent:  0, # Don't print anything to the console
    minimal: 1, # Print only errors
    quiet:   2, # Print errors and warnings
    normal:  3, # Print errors, warnings and regular encoding information
    debug:   4  # Print everything, including debug details about the encoding process
  }

  # Class default values (no NIL's here!)
  @@min_bits = 8     # Minimum code bit length
  @@max_bits = 12    # Maximum code bit length before rebuilding table
  @@lsb      = true  # Least significant bit first order
  @@clear    = true  # Use CLEAR codes
  @@stop     = true  # Use STOP codes

  # Print fixed-width LZW codes, for debugging purposes
  def self.print_codes(codes, width)
    puts "Hex Dec Binary"
    puts codes.unpack('b*')[0]
              .scan(/.{#{width}}/m)
              .map{ |c| c.reverse.to_i(2) }
              .map{ |c| "%03X %03d %0#{width}b" % [c, c, c] }
              .join("\n")
  end

  def initialize(
      preset:    nil,     # Predefined configurations (GIF...)
      bits:      nil,     # Code bit size for constant length encoding (superseeds min/max bit size)
      min_bits:  nil,     # Minimum code bit size for variable length encoding (superseeded by 'bits')
      max_bits:  nil,     # Maximum code bit size for variable length encoding (superseeded by 'bits')
      binary:    nil,     # Use binary encoding (vs regular text encoding)
      alphabet:  BINARY,  # Set of characters that compose the messages to encode
      lsb:       nil,     # Use least or most significant bit packing
      clear:     nil,     # Use clear codes every time the table gets reinitialized
      stop:      nil,     # Use stop codes at the end of the encoding
      verbosity: :normal  # Verbosity level of the encoder
    )
    # Parse preset
    params = parse_preset(preset)

    # Verbosity
    if VERBOSITY[verbosity]
      @verbosity = VERBOSITY[verbosity]
    else
      warn("Unrecognized verbosity level, using normal.")
      @verbosity = VERBOSITY[:normal]
    end

    # Alphabet
    if !alphabet.is_a?(Array) || alphabet.any?{ |a| !a.is_a?(String) || a.length > 1 }
      err('The alphabet must be an array of characters, i.e., of strings of length 1')
      exit
    end
    @alphabet = alphabet.uniq
    warn('Removed duplicate entries from alphabet') if @alphabet != alphabet

    # Binary compression
    @binary = binary.nil? ? alphabet == BINARY : binary

    # Code bit size
    if @bits
      if !@bits.is_a?(Integer) || @bits < 1
        err('Code size should be a positive integer.')
        exit
      else
        @min_bits = @bits
        @max_bits = @bits
      end
    else
      @min_bits = find_arg(min_bits, params[:min_bits], @@min_bits)
      @max_bits = find_arg(max_bits, params[:max_bits], @@max_bits)
      if @max_bits < @min_bits
        warn("Max code size (#{@max_bits}) should be higher than min code size (#{@min_bits}). Changed max code size to #{@min_bits}.")
        @max_bits = @min_bits
      end
    end

    # Alphabet length check
    if @alphabet.size > 1 << @max_bits
      if @binary
        @alphabet.take!(1 << @max_bits)
        warn("Truncated binary alphabet to #{@max_bits} bits.")
      else
        @min_bits = @alphabet.size.bit_length
        @max_bits = @min_bits if @max_bits < @min_bits
        warn("Min code size needs to fit the alphabet. Increased code sizes to #{@min_bits} - #{@max_bits}.")
      end
    end

    # Clear and stop codes
    idx = @alphabet.size - 1
    @clear = find_arg(clear, params[:clear], @@clear) ? idx += 1 : nil
    use_stop = find_arg(stop, params[:stop], @@stop)
    if !use_stop && @min_bits < 8
      use_stop = true
      warn("Stop codes are necessary for code sizes below 8 bits to prevent ambiguity. Using stop codes.")
    end
    @stop = use_stop ? idx += 1 : nil

    # Least/most significant bit packing order
    @lsb = find_arg(lsb, params[:lsb], @@lsb)
  end

  def encode(data)
    # Log
    log("LZW-encoding #{format_size(data.bytesize)} with #{format_params}.")
    stime = Time.now

    # Setup
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
    add_code(@stop) if !@stop.nil?

    # Pack codes to binary string
    res = @buffer.pack('C*')

    # Return
    ttime = Time.now - stime
    log("Encoding finished in #{"%.3fs" % [ttime]} (avg. #{"%.3f" % [(8.0 * data.bytesize / 1024) / ttime]} kbit\/s).")
    log("Encoded data: #{format_size(res.bytesize)} (#{"%5.2f%%" % [100 * (1 - res.bytesize.to_f / data.bytesize)]} compression).")
    res
  end

  # Optimization? Unpack bits subsequently, rather than converting between strings and ints
  def decode(data)
    # Log
    log("LZW-decoding #{format_size(data.bytesize)} with #{format_params}.")
    stime = Time.now

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
      break if code == @stop && @stop

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
        fresh = table_add(@table[old_code] + @table[code][0])
        out << @table[code]
      else
        fresh = table_add(@table[old_code] + @table[old_code][0])
        out << @table[-1]
      end

      # Table was initialized
      if fresh
        old_code = nil
        next
      end

      # Prepare next iteration
      old_code = code
    end

    # Return
    ttime = Time.now - stime
    log("Decoding finished in #{"%.3fs" % [ttime]} (avg. #{"%.3f" % [(8.0 * data.bytesize / 1024) / ttime]} kbit\/s).")
    log("Decoded data: #{format_size(out.bytesize)} (#{"%5.2f%%" % [100 * (1 - data.bytesize.to_f / out.bytesize)]} compression).")
    out
  end

  private

  def format_params
    log_bits = @min_bits == @max_bits ? @min_bits : "#{@min_bits}-#{@max_bits}"
    log_codes = @clear ? (@stop ? 'CLEAR & STOP codes' : 'CLEAR codes') : (@stop ? 'STOP codes' : 'no special codes')
    log_lsb = @lsb ? 'LSB' : 'MSB'
    log_binary = @binary ? 'binary' : 'textual'
    "#{log_bits} bit codes, #{log_lsb} packing, #{log_codes}, #{log_binary} mode"
  end

  def format_size(sz)
    mag = Math.log(sz, 1024).to_i.clamp(0, 3)
    unit = ['B', 'KB', 'MB', 'GB']
    "%.3f %s" % [sz.to_f / 1024 ** mag, unit[mag]]
  end

  def log(txt, level = 3)
    return if level > @verbosity
    puts "#{Time.now.strftime('[%H:%M:%S.%L]')} #{txt}"
  end

  def err(txt)
    symbol = "\x1B[31m\x1B[1m✗\x1B[0m"
    log("#{symbol} #{txt}", 1)
  end

  def warn(txt)
    symbol = "\x1B[33m\x1B[1m!\x1B[0m"
    log("#{symbol} #{txt}", 2)
  end

  def dbg(txt)
    symbol = "\x1B[90m\x1B[1mD\x1B[0m"
    log("#{symbol} #{txt}", 4)
  end

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
        clear:    true,
        stop:     true
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

  # Add new code to the table, return whether table was initialized
  def table_add(val)
    # Add code
    @key += 1
    @compress ? (@table[val] = @key; $table1 << [@key, val.bytes]) : (@table << val; $table2 << [@key, val.bytes])
    
    # Check variable width code constraints
    if @key == 1 << @bits
      if @bits == @max_bits
        add_code(@clear) if @compress && @clear
        table_init if @compress || !@clear
        return true
      else
        @bits += 1
      end
    end

    return false
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
  lzw = LZW.new(preset: :gif, clear: false)
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

# LZW-encode and decode a pixel array and see if they match
def decode_test(pixels: nil)
  lzw = LZW.new(preset: :gif)
  file = File.binread(pixels)
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
lzw = LZW.new(preset: :gif)
#encode_test(pixels: 'gifenc/pixels', gif: 'gifenc/example.gif')
decode_test(pixels: 'gifenc/pixels')
#bench_decode(pixels: 'gifenc/pixels')