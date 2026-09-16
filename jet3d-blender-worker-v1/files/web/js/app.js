import { api } from "./api.js";
import { updatePreview, renderPreviewUnavailable } from "./preview.js";

const state = { project: null, proposal: null, issues: [], online: false };
const $ = (id) => document.getElementById(id);

function nowLabel() {
  return new Intl.DateTimeFormat("pt-BR", { hour: "2-digit", minute: "2-digit" }).format(new Date());
}

function log(message, level = "info") {
  const row = document.createElement("div");
  row.dataset.level = level;
  row.innerHTML = `<time>${nowLabel()}</time><span></span>`;
  row.querySelector("span").textContent = message;
  $("activityLog").prepend(row);
}

function escapeText(value) {
  return String(value ?? "—");
}

function currentDimensions() {
  const p = state.proposal?.parameter_changes || {};
  const source = state.project?.parameters || {};
  const width = Number(p.width_mm ?? source.width_mm ?? 0);
  const depth = Number(p.depth_mm ?? source.depth_mm ?? 0);
  const height = Number(p.height_mm ?? source.height_mm ?? 0);
  return { width, depth, height };
}

function renderProject() {
  const p = state.project;
  $("revisionBadge").textContent = p ? `r${String(p.revision || 0).padStart(3, "0")}` : "r000";
  if (!p) {
    $("projectMini").innerHTML = "<span>Nenhum projeto carregado</span>";
    $("projectDetails").innerHTML = '<div><span>Projeto</span><b>—</b></div><div><span>Impressora</span><b>—</b></div><div><span>Material</span><b>—</b></div><div><span>Revisão</span><b>—</b></div>';
    return;
  }
  $("projectMini").innerHTML = `<span>Projeto ativo</span><br><b>${escapeText(p.project_name)}</b><br><code>${escapeText(p.project_id)}</code>`;
  $("projectDetails").innerHTML = `
    <div><span>Projeto</span><b>${escapeText(p.project_name)}</b></div>
    <div><span>Impressora</span><b>${escapeText(p.printer_profile)}</b></div>
    <div><span>Material</span><b>${escapeText(p.material_profile)}</b></div>
    <div><span>Revisão</span><b>r${String(p.revision || 0).padStart(3, "0")}</b></div>`;
  const d = currentDimensions();
  $("dimensionStrip").innerHTML = `<span>X ${d.width || "—"} mm</span><span>Y ${d.depth || "—"} mm</span><span>Z ${d.height || "—"} mm</span>`;
}

function renderProposal() {
  const proposal = state.proposal;
  if (!proposal) {
    $("proposalStatus").textContent = "Sem proposta";
    $("proposalContent").className = "empty-state";
    $("proposalContent").textContent = "Envie uma instrução para gerar uma proposta de revisão.";
    $("proposalActions").classList.add("hidden");
    return;
  }
  $("proposalStatus").textContent = `r${String(proposal.proposed_revision).padStart(3, "0")}`;
  const changes = Object.entries(proposal.parameter_changes || {});
  const operations = proposal.operations || [];
  $("proposalContent").className = "";
  $("proposalContent").innerHTML = `
    <div class="proposal-grid">${changes.length ? changes.map(([k,v]) => `<div class="proposal-chip"><span>${escapeText(k)}</span><b>${escapeText(v)}</b></div>`).join("") : '<div class="proposal-chip"><span>Alterações</span><b>Sem mudanças paramétricas</b></div>'}</div>
    <p class="muted">${operations.length} operação(ões) planejada(s) • base r${String(proposal.base_revision).padStart(3, "0")}</p>`;
  $("proposalActions").classList.remove("hidden");
}

function renderValidation() {
  const issues = state.issues || [];
  const counts = { BLOCKER: 0, WARNING: 0, INFO: 0 };
  issues.forEach((i) => { counts[i.severity] = (counts[i.severity] || 0) + 1; });
  $("blockerCount").textContent = counts.BLOCKER || 0;
  $("warningCount").textContent = counts.WARNING || 0;
  $("infoCount").textContent = counts.INFO || 0;
  if (!state.project) {
    $("validationList").className = "empty-state";
    $("validationList").textContent = "A validação aparecerá após carregar um projeto.";
    return;
  }
  if (!issues.length) {
    $("validationList").className = "empty-state";
    $("validationList").textContent = "Nenhum problema declarado encontrado para o projeto atual.";
    return;
  }
  $("validationList").className = "";
  $("validationList").innerHTML = issues.map((issue) => `<div class="issue"><b class="${String(issue.severity).toLowerCase()}">${escapeText(issue.severity)}</b><div><strong>${escapeText(issue.code)}</strong><br><span class="muted">${escapeText(issue.message)}</span></div></div>`).join("");
}

function renderExportReadiness() {
  const project = state.project;
  const blockers = state.issues.filter((i) => i.severity === "BLOCKER").length;
  const latestValidation = project?.validation_history?.at?.(-1) || project?.validation_history?.[project.validation_history.length - 1];
  const signatures = latestValidation?.object_signatures || {};
  const checks = [
    [Boolean(project), "Projeto carregado"],
    [Boolean(project && project.revision > 0), "Existe revisão confirmada"],
    [blockers === 0 && Boolean(project), "Sem BLOCKER na validação declarativa"],
    [Object.keys(signatures).length > 0, "Assinaturas de objetos registradas pelo pipeline Blender"],
  ];
  $("exportReadiness").innerHTML = checks.map(([ok, label]) => `<div class="check ${ok ? "ok" : ""}"><i>${ok ? "✓" : "·"}</i><span>${label}</span></div>`).join("");
  const ready = checks.every(([ok]) => ok);
  $("exportStatus").textContent = ready ? "Pronto para exportar" : "Pipeline incompleto";
}

function renderAll() {
  renderProject();
  renderProposal();
  renderValidation();
  renderExportReadiness();
  if (state.project) updatePreview(state.project, state.proposal);
  else renderPreviewUnavailable("Carregue um projeto para visualizar o envelope dimensional.");
}

async function refreshValidation() {
  if (!state.project) return;
  try {
    const result = await api.declarationValidation(state.project.project_id);
    state.issues = result?.issues || [];
    renderValidation();
    renderExportReadiness();
  } catch (error) {
    log(`Validação: ${error.message}`, "error");
  }
}

async function loadProject(projectId) {
  if (!projectId) return;
  try {
    state.project = await api.getProject(projectId.trim());
    state.proposal = null;
    localStorage.setItem("lastProjectId", state.project.project_id);
    renderAll();
    await refreshValidation();
    log(`Projeto ${state.project.project_name} carregado.`);
  } catch (error) {
    log(`Falha ao carregar projeto: ${error.message}`, "error");
  }
}

async function createProject(payload) {
  try {
    state.project = await api.createProject(payload);
    state.proposal = null;
    localStorage.setItem("lastProjectId", state.project.project_id);
    renderAll();
    await refreshValidation();
    log(`Projeto ${state.project.project_name} criado.`);
  } catch (error) {
    log(`Falha ao criar projeto: ${error.message}`, "error");
  }
}

async function interpretInstruction() {
  if (!state.project) return log("Carregue ou crie um projeto antes de interpretar instruções.", "warning");
  const instruction = $("instructionInput").value.trim();
  if (!instruction) return log("Digite uma instrução de engenharia.", "warning");
  try {
    state.proposal = await api.interpret(state.project.project_id, instruction);
    renderProposal();
    renderProject();
    renderExportReadiness();
    log(`Proposta ${state.proposal.proposal_id} preparada para revisão.`);
  } catch (error) {
    log(`Interpretação recusada: ${error.message}`, "error");
  }
}

async function commitProposal() {
  if (!state.project || !state.proposal) return;
  try {
    const validation = state.issues || [];
    await api.commitProposal(state.project.project_id, state.proposal.proposal_id, {
      proposal_id: state.proposal.proposal_id,
      validation,
      object_signatures: {},
    });
    const id = state.project.project_id;
    state.proposal = null;
    await loadProject(id);
    log("Revisão confirmada. Sincronizando geometria de fabricação no Blender…");
    const manufacturing = await api.manufacturingSync(id, { export_version: 1, acknowledged_warning_codes: [] });
    await loadProject(id);
    log(`Geometria de fabricação sincronizada pelo Blender. Status: ${manufacturing.status}.`);
  } catch (error) {
    log(`Falha ao confirmar revisão: ${error.message}`, "error");
  }
}

async function discardProposal() {
  if (!state.project || !state.proposal) return;
  try {
    await api.discardProposal(state.project.project_id, state.proposal.proposal_id);
    state.proposal = null;
    renderProposal();
    renderProject();
    log("Proposta descartada.");
  } catch (error) {
    log(`Falha ao descartar proposta: ${error.message}`, "error");
  }
}

async function checkHealth() {
  try {
    const result = await api.health();
    state.online = result?.status === "ok";
  } catch {
    state.online = false;
  }
  $("healthPill").className = `health-pill ${state.online ? "online" : "offline"}`;
  $("healthPill").querySelector("b").textContent = state.online ? "API operacional" : "API indisponível";
}

$("createProjectForm").addEventListener("submit", (event) => {
  event.preventDefault();
  createProject({ name: $("projectName").value.trim(), printer_profile: $("printerProfile").value, material_profile: $("materialProfile").value });
});
$("loadProjectForm").addEventListener("submit", (event) => { event.preventDefault(); loadProject($("existingProjectId").value); });
$("interpretBtn").addEventListener("click", interpretInstruction);
$("commitBtn").addEventListener("click", commitProposal);
$("discardBtn").addEventListener("click", discardProposal);
$("refreshBtn").addEventListener("click", () => state.project && loadProject(state.project.project_id));
$("clearLogBtn").addEventListener("click", () => { $("activityLog").innerHTML = ""; });

checkHealth();
renderAll();
const lastProjectId = localStorage.getItem("lastProjectId");
if (lastProjectId) { $("existingProjectId").value = lastProjectId; loadProject(lastProjectId); }

export { createProject, loadProject, interpretInstruction, commitProposal, discardProposal, refreshValidation };
