require 'set'
module OSC
  class Pattern < OSCString
    def initialize(s)
      case s
      when Regexp # This is experimental
	s = Regexp.source s
	s.gsub! /(\\\\)*\[^\/\]\*/, "\1*"
	s.gsub! /(\\\\)*\[^\/\]/, "\1?"
	s.gsub! /(\\\\)*\[^/, "\1[!"
	s.gsub! /(\\\\)*\(/, "\1{"
	s.gsub! /(\\\\)*\|/, "\1,"
	s.gsub! /(\\\\)*\)/, "\1}"
	s.gsub! /\\\\/, "\\"
      end
      @val = s.to_s
    end

    def regexp
      s = Regexp.escape @val
      s.gsub! /\\\?/, '[^/]'
      s.gsub! /\\\*/, '[^/]*'
      s.gsub! /\\\[!/, '[^'
      s.gsub! /\\\]/, ']'
      s.gsub! /\\\{/, '('
      s.gsub! /,/, '|'
      s.gsub! /\\\}/, ')'
      Regexp.new s
    end

    # Do these two patterns intersect?
    def self.intersect?(s1,s2)
      r = /\*|\?|\[[^\]]*\]|\{[^\}]*\}|./
      a = s1.to_s.scan r
      b = s2.to_s.scan r
      q = [[a,b]]
      until q.empty?
	q.uniq!
	a,b = q.pop
	a = a.dup
	b = b.dup

	return true if a.empty? and b.empty?
	next if a.empty? or b.empty?

	x,y = a.shift, b.shift

	# branch {}
	if x =~ /^\{/
	  x.scan /[^\{\},]+/ do |x|
	    q.push [x.scan(/./)+a,[y]+b]
	  end
	  next
	end
	if y =~ /^\{/
	  y.scan /[^\{\},]+/ do |y|
	    q.push [[x]+a,y.scan(/./)+b]
	  end
	  next
	end

	# sort
	if y =~ /^\[/
	  x,y = y,x
	  a,b = b,a
	end
	if y =~ /^(\*|\?)/
	  x,y = y,x
	  a,b = b,a
	end

	# match
	case x
	when '*'
	  unless y == '/'
	    q.push [a,b]
	    q.push [[x]+a,b]
	  end
	  if y == '*'
	    q.push [a,[y]+b]
	    q.push [[x]+a,b]
	  end
	when '?'
	  q.push [a,b] unless y == '/'
	  q.push [a,[y]+b] if y == '*'
	when /^\[/
	  xinv = (x[1] == ?!)
	  yinv = (y =~ /^\[!/)
	  x = x[(xinv ? 2 : 1)..-2].scan(/./).to_set
	  if y =~ /^\[/
	    y = y[(yinv ? 2 : 1)..-2].scan(/./).to_set
	  else
	    y = [y].to_set
	  end

	  # simplifying assumption: nobody in their right mind is going to do
	  # [^everyprintablecharacter]
	  if xinv and yinv
	    q.push [a,b]
	  elsif xinv and not yinv
	    q.push [a,b] unless (y-x).empty?
	  elsif not xinv and yinv
	    q.push [a,b] unless (x-y).empty?
	  else
	    q.push [a,b] unless (x&y).empty?
	  end
	else
	  q.push [a,b] if x == y
	end
      end

      false # no intersection
    end
  end
end
