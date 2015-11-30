describe 'xo' do
  it 'works' do    
    # Kills the unfortunate worker that tries to run it
    Process.kill(:KILL, Process.pid)
  end
end
