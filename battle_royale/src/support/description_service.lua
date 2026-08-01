local M = {}

function M.sendDescription(session)
  for _, handle in ipairs(session.players()) do
    local description = session.config.translationList(handle, "description")
    for _, line in ipairs(description) do
      session.messages.sendRaw(handle, line)
    end
  end
end

return M
