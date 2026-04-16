require_relative '../../core/framework/glauco-framework'

class FloatingChatRuntime
  def app_name(*)
    'Glauco Framework'
  end

  def app_summary(*)
    'Aplicacao desktop com interface principal e chat flutuante para onboarding, suporte e vendas.'
  end

  def quick_actions(*)
    [
      'Quero ver os planos disponiveis',
      'Como funciona a implantacao?',
      'Preciso falar com vendas',
      'Mostre um resumo do produto'
    ]
  end

  def recommended_next_step(topic = nil, *)
    'Proximo passo recomendado: Conduzir a conversa para o proximo passo util.'
  end
end

class FloatingChatAgent < GlaucoLLM
  SYSTEM_CONFIG_PATH = File.expand_path('../../examples/floating_chat_system.md', __dir__)

  def initialize
    super()

    bootstrap_agent!(
      system_config_instructions: SYSTEM_CONFIG_PATH,
      runtime: FloatingChatRuntime.new
    )
  end
end

agent = FloatingChatAgent.new
puts '--- RESULT ---'
puts agent.interpretar('Quero um resumo curto do produto')
