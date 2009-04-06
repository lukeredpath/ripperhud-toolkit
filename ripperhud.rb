require 'rubygems'
require 'sinatra'

RIP_FOLDER = File.join('/Volumes', 'Media', 'DVD Rips')
RIP_MACHINE = '192.168.0.2'
RIP_USER = 'luke'

class Ripperhud
  def initialize(host, user, ripper_path, ts_path='/usr/local/bin/ts')
    @host = host
    @user = user
    @ripper_path = ripper_path
    @ts_path = ts_path
  end
  
  def process(file_name, params)
    episode_range = Range.new(params[:episode_from].to_i, params[:episode_to].to_i)
    command = ripper_command(file_name, params[:type], params[:name], params[:duration], episode_range, params[:season], params[:duration_variance], params[:track_offset])
    execute_remotely("#{@ts_path} #{command}", "#{@ts_path} -u")
  end
  
  def raw_ts_list
    @raw_ts_list ||= execute_and_return("#{@ts_path} -l")
  end
  
  def class_for_rip(rip)
    if encoding?(rip)
      return 'running'
    elsif queued?(rip)
      return 'queued'
    elsif pending?(rip)
      return 'pending'
    else
      return 'new'
    end
  end
  
  def pending_encodes
    @pending_encodes ||= queued_jobs.grep(/ripper/).map do |line| 
      File.basename(line.match(/ripper (.*)\.dvdmedia/)[1]) + '.dvdmedia'
    end
  end
  
  def queued_encodes
    @queued_encodes ||= queued_jobs.grep(/HandBrakeCLI/).map do |line|
      File.basename(line.match(/-i (.*)\.dvdmedia/)[1]) + '.dvdmedia'
    end
  end
  
  def pending?(rip)
    pending_encodes.include?(File.basename(rip))
  end
  
  def queued?(rip)
    queued_encodes.include?(File.basename(rip))
  end
  
  def encoding?(rip)
    return false unless running_job
    running_job.match(File.basename(rip))
  end
  
  private
  
  def ripper_command(input, type, name, duration, episode_range, season, duration_variance, track_offset)
    if type == 'film'
      "#{@ripper_path} --input-file #{escape(input)} --input-type #{type} --name #{escape(name)}"
    else
      "#{@ripper_path} --input-file #{escape(input)} --input-type #{type} --name #{escape(name)} --episode-duration #{duration} --episode-range #{episode_range} --season #{season} --duration-variance #{duration_variance} --track-offset #{track_offset}"
    end
  end
  
  def execute_remotely(*commands)
    system("ssh #{@user}@#{@host} '#{commands.join(' ; ')}\'")
  end
  
  def execute_and_return(*commands)
    `ssh #{@user}@#{@host} \"#{commands.join(' ; ')}\"`
  end
  
  def job_list
    @job_list ||= raw_ts_list.split("\n").grep(/^\d/)
  end
  
  def queued_jobs
    job_list.grep(/queued/)
  end
  
  def running_job
    job_list.grep(/running/).first
  end
  
  def escape(string)
    string.gsub(/\s/, '\ ')
  end
end

get '/' do
  @ripperhud = Ripperhud.new(RIP_MACHINE, RIP_USER, '/Users/luke/.bin/ripper')
  @rips = Dir[File.join(RIP_FOLDER, '*.dvdmedia')]
  haml :index
end

get '/queue' do
  hud = Ripperhud.new(RIP_MACHINE, RIP_USER, '/Users/luke/.bin/ripper')
  header['content-type'] = 'text/plain'
  hud.raw_ts_list
end

post '/process' do
  hud = Ripperhud.new(RIP_MACHINE, RIP_USER, '/Users/luke/.bin/ripper')
  hud.process(params[:filename], params[:ripper])
  redirect '/'
end