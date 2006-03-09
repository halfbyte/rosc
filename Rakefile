require 'rake/testtask'
require 'rake/rdoctask'

Rake::RDocTask.new do |rd|
  rd.rdoc_dir = 'doc'
  rd.options = ['-x_darcs','-xtest']
end

Rake::TestTask.new do |t|
  #t.verbose = true
end

# vim: filetype=ruby
