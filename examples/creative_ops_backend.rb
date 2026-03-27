module CreativeOpsBackend
  module_function

  CAMPAIGNS = [
    {
      id: 101,
      name: "Pulse Atlas Launch",
      owner: "Ana",
      channel: "Email",
      status: "Review",
      priority: "High",
      score: 92,
      due_in: "2h",
      notes: "Hero visual pronto; CTA ainda sem aprovacao final."
    },
    {
      id: 102,
      name: "Northwind Retention Burst",
      owner: "Bruno",
      channel: "Social",
      status: "Draft",
      priority: "Medium",
      score: 74,
      due_in: "Tomorrow",
      notes: "Legenda forte, mas a variacao mobile ainda parece apertada."
    },
    {
      id: 103,
      name: "Luma Partner Spotlight",
      owner: "Carla",
      channel: "Push",
      status: "Live",
      priority: "Low",
      score: 88,
      due_in: "Live",
      notes: "Entrega publicada; monitorando CTR e rejeicao nos primeiros blocos."
    },
    {
      id: 104,
      name: "Orbit Studio Teaser",
      owner: "Dora",
      channel: "Email",
      status: "Review",
      priority: "High",
      score: 81,
      due_in: "5h",
      notes: "A headline esta forte, mas a secao de prova social ainda pede ajuste."
    },
    {
      id: 105,
      name: "Signal Winter Promo",
      owner: "Ana",
      channel: "Social",
      status: "Paused",
      priority: "High",
      score: 63,
      due_in: "Blocked",
      notes: "Pausada por risco de conflito visual com a campanha institucional."
    }
  ].freeze

  ALERTS = [
    {
      id: "alert-1",
      kind: "warning",
      title: "Risco de consistencia",
      subtitle: "Duas campanhas usam claims semelhantes para audiencias vizinhas."
    },
    {
      id: "alert-2",
      kind: "info",
      title: "Fila carregada",
      subtitle: "A revisao de criativos esta 18% acima da media da semana."
    }
  ].freeze

  ACTIVITY = [
    "09:12 -> Ana marcou Pulse Atlas como pronto para compliance.",
    "09:04 -> Dora anexou nova versao de Orbit Studio com CTA enxuto.",
    "08:58 -> Carla confirmou rollout de Luma Partner Spotlight.",
    "08:41 -> Bruno reabriu Northwind Retention Burst para ajuste de copy."
  ].freeze

  TIMELINE = {
    101 => [
      "Layout hero aprovado pelo time de marca.",
      "CTA alternativo aguardando validacao legal.",
      "Snapshot mobile enviado para revisao final."
    ],
    102 => [
      "Storyboard inicial validado.",
      "Variacao vertical precisa de respiro no topo.",
      "Hooks de remarketing em refinamento."
    ],
    103 => [
      "Campanha publicada em todos os touchpoints.",
      "CTR inicial acima da meta em 11%.",
      "Sem sinais de fadiga criativa nas primeiras 3h."
    ],
    104 => [
      "Review visual concluida pelo design.",
      "Equipe de growth pediu CTA mais direto.",
      "Aguardando aprovacao de budget para boost."
    ],
    105 => [
      "Campanha pausada apos overlap com promocao institucional.",
      "Nova proposta de tom em preparacao.",
      "Replanejamento previsto para o fim do dia."
    ]
  }.freeze

  def dashboard_summary(filters = {})
    campaigns = apply_workspace_filters(filters)

    {
      total: campaigns.length,
      review: campaigns.count { |campaign| campaign[:status] == "Review" },
      live: campaigns.count { |campaign| campaign[:status] == "Live" },
      risk: campaigns.count { |campaign| campaign[:priority] == "High" || campaign[:status] == "Paused" }
    }
  end

  def load_campaigns(filters = {}, simulate_error: false)
    simulate_latency
    raise "Backend local indisponivel para esta consulta." if simulate_error

    apply_workspace_filters(filters)
  end

  def load_timeline(campaign_id)
    simulate_latency(0.12)
    deep_dup(TIMELINE[campaign_id] || [])
  end

  def load_alerts(_filters = {})
    simulate_latency(0.08)
    deep_dup(ALERTS)
  end

  def load_activity_feed(_filters = {})
    simulate_latency(0.08)
    deep_dup(ACTIVITY)
  end

  def save_review_decision(campaign_id, action)
    simulate_latency(0.25)

    raise "Falha simulada ao salvar decisao." if action.to_s == "simulate_error"

    campaign = CAMPAIGNS.find { |item| item[:id] == campaign_id }
    raise "Campanha #{campaign_id} nao encontrada." unless campaign

    updated = deep_dup(campaign)
    activity_entry = nil
    alert = nil

    case action.to_s
    when "approve"
      updated[:status] = "Live"
      updated[:score] = [updated[:score] + 4, 99].min
      updated[:due_in] = "Live"
      activity_entry = "#{timestamp} -> #{updated[:name]} aprovada e enviada para publicacao."
    when "pause"
      updated[:status] = "Paused"
      updated[:score] = [updated[:score] - 6, 10].max
      updated[:due_in] = "Blocked"
      activity_entry = "#{timestamp} -> #{updated[:name]} pausada para ajuste de narrativa."
      alert = {
        id: "alert-pause-#{campaign_id}",
        kind: "warning",
        title: "Campanha pausada",
        subtitle: "#{updated[:name]} saiu da fila ativa e agora pede revisao de copy."
      }
    when "flag"
      updated[:status] = "Review"
      updated[:priority] = "High"
      updated[:score] = [updated[:score] - 3, 10].max
      activity_entry = "#{timestamp} -> #{updated[:name]} marcada para revisao criativa urgente."
      alert = {
        id: "alert-flag-#{campaign_id}",
        kind: "error",
        title: "Escalada criativa",
        subtitle: "#{updated[:name]} foi enviada para triagem prioritara."
      }
    else
      raise "Acao #{action} nao suportada."
    end

    {
      campaign: updated,
      activity_entry: activity_entry,
      alert: alert
    }
  end

  def apply_workspace_filters(filters = {})
    selected_status = fetch(filters, :status, "All")
    selected_channel = fetch(filters, :channel, "All")
    selected_owner = fetch(filters, :owner, "All")

    campaigns = deep_dup(CAMPAIGNS)

    campaigns.select do |campaign|
      status_match = selected_status == "All" || campaign[:status] == selected_status
      channel_match = selected_channel == "All" || campaign[:channel] == selected_channel
      owner_match = selected_owner == "All" || campaign[:owner] == selected_owner

      status_match && channel_match && owner_match
    end
  end

  def simulate_latency(base = 0.18)
    sleep(base)
  end

  def timestamp
    Time.now.strftime("%H:%M")
  end

  def deep_dup(value)
    Marshal.load(Marshal.dump(value))
  end

  def fetch(hash, key, default_value)
    return default_value unless hash

    hash[key] || hash[key.to_s] || default_value
  end
end
