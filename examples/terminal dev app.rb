# Demo interativa de terminal usando o browser embutido do Glauco Framework.

require_relative '../core/framework/glauco-framework'

agent = GlaucoAgentBrowserEnv.new(visible: true)

def banner(title)
  puts "\n" + "=" * 80
  puts "TESTE: #{title}"
  puts "=" * 80
end

def safe_exec(agent, input)
  puts "\n[Test] Entrada: #{input.inspect}"
  result = agent.interpretar(input)
  puts "[Test] Resultado: #{result.inspect}"
rescue => e
  puts "[Test] 💥 Erro: #{e.class} - #{e.message}"
end

banner('MODO CONSOLE INTERATIVO COM BROWSER')

puts "Digite comandos de automação (ex: 'abrir google.com')"
puts "O browser embutido do GlaucoAgentBrowserEnv sera aberto para navegar."
puts "Digite 'exit' ou 'sair' para encerrar.\n\n"

loop do
  print '>> '
  input = STDIN.gets&.strip&.dup
  break if input.nil? || input.downcase == 'exit' || input.downcase == 'sair'

  if input.empty?
    puts '[Console] ⚠️ Entrada vazia ignorada.'
    next
  end

  puts input.frozen?
  safe_exec(agent, input)
  puts input.frozen?
end

puts '[Console] ✅ Sessão encerrada.'
