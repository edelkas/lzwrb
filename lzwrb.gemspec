Gem::Specification.new do |s|
  s.name        = "lzwrb"
  s.version     = "0.1.0"
  s.summary     = "Pure Ruby LZW encoder/decoder, highly configurable, compatible with GIF"
  s.description = <<-EOT
    This library provides LZW encoding and decoding capabilities with no
    dependencies and a reasonably fast speed. It is highly configurable,
    supporting both constant and variable code lengths, custom alphabets,
    usage of clear/stop codes...

    It is compatible with the GIF specification, and comes equipped with
    several presets. Eventually I'd like to add compatibility with other
    standards, such as the ones used for UNIX compress, PDF and TIFF.
  EOT
  s.authors     = ["edelkas"]
  s.files       = ["lib/lzwrb.rb"]
  s.homepage    = "https://github.com/edelkas/lzwrb"
  s.metadata = {
    "source_code_uri" => "https://github.com/edelkas/lzwrb"
  }
end
