if (ARGV.size != 2)
  puts "You need to supply the width and height."
  exit
end

w, h = ARGV[0].to_i, ARGV[1].to_i
if (w.to_s != ARGV[0] || h.to_s != ARGV[1])
  puts "The arguments need to be integers (width, height)."
  exit
end

File.binwrite('pixels', (w * h).times.map{ |b| (256 * rand).to_i }.pack('C*'))