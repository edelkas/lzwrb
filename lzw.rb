class LZW
  # Class default values (no NIL's here!)
  @@min_bits = 8     # Minimum code bit length
  @@max_bits = 12    # Maximum code bit length before rebuilding dictionary
  @@lsb      = true  # Least significant bit first order
  @@codes    = true  # Use CLEAR and STOP codes (VALUES = 2 ** min_bits + {0, 1})

  # TODO: Allow min_bits over 8 bits (dict keys will have to be packed)
  # TODO: Optimize by using Trie rather than standard Hash
  def initialize(preset: nil, min_bits: nil, max_bits: nil, lsb: nil, codes: nil)
    # Parse params (preset and individual)
    params = parse_preset(preset)
    use_codes = find_arg(codes, params[:codes], @@codes)

    @min_bits = find_arg(min_bits, params[:min_bits], @@min_bits)
    @max_bits = find_arg(max_bits, params[:max_bits], @@max_bits)
    @lsb      = find_arg(lsb, params[:lsb], @@lsb)
    @clear    = use_codes ? 1 << @min_bits : nil
    @stop     = use_codes ? @clear + 1     : nil
  end

  def compress(data)
    # Initialize output and dictionary
    init
    dict_init

    # LZW-encode data
    buf = data.first
    data.each_char do |c|
      new = buf + c
      if dict_has(new)
        buf = new
      else
        add_code(buf)
        dict_add(new)
        buf = c
      end
    end
    add_code(@stop) if !@stop.nil?

    # Pack codes to binary string
    codes.pack('C*')
  end

  private

  # Return first non-nil argument
  def find_arg(*args)
    args.each{ |arg| arg.nil? ? next : return arg }
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
    @dict = (0 .. @key).times.map{ |i| [i.chr, i] }.to_h

    # Increment key index if clear/stop symbols are being used
    @key += 1 if !@clear.nil?
    @key += 1 if !@stop.nil?
    @bits = @key.bit_length

    # Output clear code if necessary
    add_code(@clear) if !@clear.nil?
  end

  def dict_has(str)
    @dict.include?(str)
  end

  # Add new code to the dictionary
  def dict_add(str)
    # Add code
    @key += 1
    @dict[str] = @key
    
    # Check variable width code constraints
    if @key == 1 << @bits
      if @bits == @max_bits
        dict_init
      else
        @bits += 1
      end
    end
  end

  def add_code(code)
    
  end

end
