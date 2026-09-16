const API_PREFIX = "/api";

async function request(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
  });
  const text = await response.text();
  let body = null;
  if (text) {
    try { body = JSON.parse(text); } catch { body = { detail: text }; }
  }
  if (!response.ok) {
    const message = body?.detail || `${response.status} ${response.statusText}`;
    throw new Error(message);
  }
  return body;
}

export const api = {
  health: () => request("/health", { headers: {} }),
  createProject: (payload) => request(`${API_PREFIX}/projects`, { method: "POST", body: JSON.stringify(payload) }),
  getProject: (id) => request(`${API_PREFIX}/projects/${encodeURIComponent(id)}`),
  interpret: (id, instruction) => request(`${API_PREFIX}/projects/${encodeURIComponent(id)}/interpret`, { method: "POST", body: JSON.stringify({ instruction }) }),
  commitProposal: (id, proposal, payload) => request(`${API_PREFIX}/projects/${encodeURIComponent(id)}/revisions/${encodeURIComponent(proposal)}/commit`, { method: "POST", body: JSON.stringify(payload) }),
  discardProposal: (id, proposal) => request(`${API_PREFIX}/projects/${encodeURIComponent(id)}/revisions/${encodeURIComponent(proposal)}`, { method: "DELETE" }),
  declarationValidation: (id) => request(`${API_PREFIX}/projects/${encodeURIComponent(id)}/declaration-validation`),
  printerProfile: (name) => request(`${API_PREFIX}/profiles/printers/${encodeURIComponent(name)}`),
  materialProfile: (name) => request(`${API_PREFIX}/profiles/materials/${encodeURIComponent(name)}`),
  manufacturingSync: (id, payload = {}) => request(`${API_PREFIX}/projects/${encodeURIComponent(id)}/manufacturing/sync`, { method: "POST", body: JSON.stringify(payload) }),
  manufacturingStatus: (id) => request(`${API_PREFIX}/projects/${encodeURIComponent(id)}/manufacturing/status`),
};
