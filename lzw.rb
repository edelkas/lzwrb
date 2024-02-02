class LZW

  # Default alphabets
  DEC         = (0...10).to_a.map(&:chr)
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

  # Default presets
  PRESET_GIF = {
    min_bits: 8,
    max_bits: 12,
    lsb:      true,
    clear:    true,
    stop:     true,
    deferred: true
  }
  PRESET_FAST = {
    min_bits: 16,
    max_bits: 16,
    lsb:      true,
    clear:    false,
    stop:     false
  }
  PRESET_BEST = {
    min_bits: 8,
    max_bits: 16,
    lsb:      true,
    clear:    false,
    stop:     false
  }

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
  @@max_bits = 16    # Maximum code bit length before rebuilding table
  @@lsb      = true  # Least significant bit first order
  @@clear    = false # Use CLEAR codes
  @@stop     = false # Use STOP codes
  @@deferred = false # Use deferred CLEAR codes

  def initialize(
      preset:    nil,     # Predefined configurations (GIF...)
      bits:      nil,     # Code bit size for constant length encoding (superseeds min/max bit size)
      min_bits:  nil,     # Minimum code bit size for variable length encoding (superseeded by 'bits')
      max_bits:  nil,     # Maximum code bit size for variable length encoding (superseeded by 'bits')
      binary:    nil,     # Use binary encoding (vs regular text encoding)
      alphabet:  BINARY,  # Set of characters that compose the messages to encode
      safe:      false,   # First encoding pass to verify alphabet covers all data
      lsb:       nil,     # Use least or most significant bit packing
      clear:     nil,     # Use clear codes every time the table gets reinitialized
      stop:      nil,     # Use stop codes at the end of the encoding
      deferred:  nil,     # Use deferred clear codes
      verbosity: :normal  # Verbosity level of the encoder
    )
    # Parse preset
    params = preset || {}

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
    warn('Removed duplicate entries from alphabet') if @alphabet.size < alphabet.size

    # Binary compression
    @binary = binary.nil? ? alphabet == BINARY : binary

    # Safe mode for encoding (verifies that the data provided is composed exclusively
    # by characters from the alphabet)
    @safe = safe

    # Code bit size
    if bits
      if !bits.is_a?(Integer) || bits < 1
        err('Code size should be a positive integer.')
        exit
      else
        @min_bits = bits
        @max_bits = bits
      end
    else
      @min_bits = find_arg(min_bits, params[:min_bits], @@min_bits)
      @max_bits = find_arg(max_bits, params[:max_bits], @@max_bits)
      if @max_bits < @min_bits
        warn("Max code size (#{@max_bits}) should be higher than min code size (#{@min_bits}): changed max code size to #{@min_bits}.")
        @max_bits = @min_bits
      end
    end

    # Determine min bits based on alphabet length if not specified
    if !find_arg(min_bits, params[:min_bits])
      @min_bits = (@alphabet.size - 1).bit_length
      @max_bits = @min_bits if @max_bits < @min_bits
    end

    # Clear and stop codes
    use_clear = find_arg(clear, params[:clear], @@clear)
    use_stop = find_arg(stop, params[:stop], @@stop)
    if !use_stop && @min_bits < 8
      use_stop = true
      # Warning if stop codes were explicitly disabled (false, NOT nil)
      if find_arg(stop, params[:stop]) == false
        warn("Stop codes are necessary for code sizes below 8 bits to prevent ambiguity: enabled stop codes.")
      end
    end

    # Alphabet length checks
    extra = (use_clear ? 1 : 0) + (use_stop ? 1 : 0)
      # Max bits doesn't fit alphabet (needs explicit adjustment)
    if (@alphabet.size + extra) > 1 << @max_bits
      if @binary
        @alphabet = @alphabet.take((1 << @max_bits - 1))
        warn("Using #{@max_bits - 1} bit binary alphabet (#{(1 << @max_bits - 1)} entries).")
      else
        @max_bits = (@alphabet.size + extra).bit_length
        warn("Max code size needs to fit the alphabet (and clear & stop codes, if used): increased to #{@max_bits} bits.")
      end
    end
      # Min bits doesn't fit alphabet (needs implicit adjustment)
    if (@alphabet.size + extra) > 1 << @min_bits
      @min_bits = (@alphabet.size + extra - 1).bit_length
    end

    # Clear and stop codes
    idx = @alphabet.size - 1
    @clear = use_clear ? idx += 1 : nil
    @stop = use_stop ? idx += 1 : nil
    @deferred = find_arg(deferred, params[:deferred], @@deferred)

    # Least/most significant bit packing order
    @lsb = find_arg(lsb, params[:lsb], @@lsb)
  end

  def encode(data)
    # Log
    log("<- Encoding #{format_size(data.bytesize)} with #{format_params}.")
    stime = Time.now

    # Setup
    init(true)
    table_init
    verify_data(data) if @safe

    # LZW-encode data
    buf = ''
    put_code(@clear) if !@clear.nil?
    data.each_char do |c|
      next_buf = buf + c
      if table_has(next_buf)
        buf = next_buf
      else
        put_code(@table[buf])
        table_add(next_buf)
        table_check()
        buf = c
      end
    end
    put_code(@table[buf])
    put_code(@stop) if !@stop.nil?

    # Pack codes to binary string
    res = @buffer.pack('C*')

    # Return
    ttime = Time.now - stime
    log("-> Encoding finished in #{"%.3fs" % [ttime]} (avg. #{"%.3f" % [(8.0 * data.bytesize / 1024 ** 2) / ttime]} mbit\/s).")
    log("-> Encoded data: #{format_size(res.bytesize)} (#{"%5.2f%%" % [100 * (1 - res.bytesize.to_f / data.bytesize)]} compression).")
    res
  rescue => e
    lex(e, 'Encoding error', true)
  end

  # Optimization? Unpack bits subsequently, rather than converting between strings and ints
  def decode(data)
    # Log
    log("<- Decoding #{format_size(data.bytesize)} with #{format_params}.")
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
    width = @bits
    while off + width <= len
      # Parse code
      code = bits[off ... off + width].reverse.to_i(2)
      off += width

      # Handle clear and stop codes, if present
      if code == @clear && @clear
        table_init
        old_code = nil
        width = @bits
        next
      end
      break if code == @stop && @stop

      # Handle regular codes
      if old_code.nil?        # Initial code
        out << @table[code]
      elsif table_has(code)   # Existing code
        out << @table[code]
        table_add(@table[old_code] + @table[code][0])
      else                    # New code
        out << @table[old_code] + @table[old_code][0]
        table_add(@table[old_code] + @table[old_code][0])
      end

      # Prepare next iteration
      old_code = table_check ? nil : code
      width = @bits unless !old_code && @clear
    end

    # Return
    ttime = Time.now - stime
    log("-> Decoding finished in #{"%.3fs" % [ttime]} (avg. #{"%.3f" % [(8.0 * data.bytesize / 1024 ** 2) / ttime]} mbit\/s).")
    log("-> Decoded data: #{format_size(out.bytesize)} (#{"%5.2f%%" % [100 * (1 - data.bytesize.to_f / out.bytesize)]} compression).")
    out
  rescue => e
    lex(e, 'Decoding error', false)
  end

  private

  # Initialize buffers, needs to be called every time we execute a new
  # compression / decompression job
  def init(compress)
    @buffer = []              # Contains result of compression
    @boff = 0                 # BIT offset of last buffer byte, for packing
    @compress = compress      # Compression or decompression job
    @step = @compress ? 0 : 1 # Decoder is always 1 step behind the encoder
  end

  # < --------------------------- PARSING METHODS ---------------------------- >

  # Return first non-nil argument
  def find_arg(*args)
    args.each{ |arg| arg.nil? ? next : (return arg) }
    nil
  end

  # < --------------------------- LOGGING METHODS ---------------------------- >

  def format_params
    log_bits = @min_bits == @max_bits ? @min_bits : "#{@min_bits}-#{@max_bits}"
    log_codes = @clear ? (@stop ? 'CLEAR & STOP codes' : 'CLEAR codes') : (@stop ? 'STOP codes' : 'no special codes')
    log_lsb = @lsb ? 'LSB' : 'MSB'
    log_binary = @binary ? 'binary' : 'textual'
    "#{log_bits} bit codes, #{log_lsb} packing, #{log_codes}, #{log_binary} mode"
  end

  def format_size(sz)
    mag = Math.log(sz, 1024).to_i.clamp(0, 3)
    unit = ['B', 'KiB', 'MiB', 'GiB']
    fmt = mag == 0 ? '%d' : '%.3f'
    "#{fmt}%s" % [sz.to_f / 1024 ** mag, unit[mag]]
  end

  def log(txt, level = 3)
    return if level > @verbosity
    puts "#{Time.now.strftime('[%H:%M:%S.%L]')} LZW #{txt}"
  end

  def err(txt)  log("\x1B[31m\x1B[1m✗\x1B[0m \x1B[31m#{txt}\x1B[0m", 1) end
  def warn(txt) log("\x1B[33m\x1B[1m!\x1B[0m \x1B[33m#{txt}\x1B[0m", 2) end
  def dbg(txt)  log("\x1B[90m\x1B[1mD\x1B[0m \x1B[90m#{txt}\x1B[0m", 4) end

  def lex(e, msg = '', fatal = false)
    err("#{msg}: #{e}")
    dbg(e.backtrace.unshift('Backtrace:').join("\n"))
    exit(1) if fatal
  end

    # < --------------------------- TABLE METHODS ---------------------------- >

  # Initializes the table, needs to be called at the start of each compression
  # / decompression job, as well as whenever the table gets full, which may
  # happen many times in a single job.
  #
  # During compression, the table is a hash. During decompression, the table
  # is an array, making the job faster.
  def table_init
    # Add symbols for all strings of length 1 (e.g. all 256 byte values)
    @key = @alphabet.size - 1
    @table = @compress ? @alphabet.each_with_index.to_h : @alphabet.dup

    # Increment key index if clear/stop symbols are being used
    if @clear
      @key += 1
      @table << '' if !@compress
    end
    if @stop
      @key += 1
      @table << '' if !@compress
    end

    @bits = [@key.bit_length, @min_bits].max
  end

  def table_has(val)
    @compress ? @table.include?(val) : @key >= val
  end

  # Add new code to the table
  def table_add(val)
    # Table is full
    return if @key + @step >= 1 << @max_bits

    # Add code and increase index
    @key += 1
    @compress ? @table[val] = @key : @table << val
  end

  # Check table size, and increase code length or reinitialize if needed
  def table_check
    if @key + @step == 1 << @bits
      if @bits == @max_bits
        put_code(@clear) if @compress && @clear
        refresh = @compress || !@clear || !@deferred
        table_init if refresh
        return refresh
      else
        @bits += 1
      end
    end
    return false
  end

  # < ------------------------- ENCODING METHODS --------------------------- >

  def verify_data(data)
    alph = @alphabet.each_with_index.to_h
    raise "Data contains characters not present in the alphabet" if data.each_char.any?{ |c| !alph.include?(c) }
  end

  def put_code(code)
    raise 'Found character not in alphabet' if code.nil?
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

end
