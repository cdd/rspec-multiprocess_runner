describe 'ax' do
  it 'works' do
    # Forcefully kill the unlucky worker who gets this file
    sleep 0.5
    Process.kill(:KILL, Process.pid)
  end
end
