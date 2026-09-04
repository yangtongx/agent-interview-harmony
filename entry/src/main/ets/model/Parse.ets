import { asBool, asNumber, asObjectArray, asRecord, asString, asStringArray } from '../common/JsonUtil';
import { AnswerBlock, AilianIntro, AuthUser, BankStats, CandidateProfile, HomeCard, HomePayload, JudgeResult, LlmSettings, MockTurn, Question, ResumeArchive, ResumeJob, ResumeProfile, ResumeProject, SessionPayload, Topic, chatModelFor, presetFor } from './Types';

function parsePoints(raw: Object | undefined): AnswerBlock[] {
  const list = asObjectArray(raw);
  const out: AnswerBlock[] = [];
  for (let i = 0; i < list.length; i++) {
    const row = asRecord(list[i]);
    const block = new AnswerBlock();
    block.heading = asString(row['heading']);
    block.body = asString(row['body']);
    out.push(block);
  }
  return out;
}

export function parseQuestion(raw: Object): Question {
  const row = asRecord(raw);
  const q = new Question();
  q.id = asString(row['id']);
  q.parentId = asString(row['parentId']);
  q.prerequisiteId = asString(row['prerequisiteId']);
  q.level = asNumber(row['level'], 1);
  q.topicId = asString(row['topicId']);
  q.difficulty = asString(row['difficulty'], '基础');
  q.angle = asString(row['angle']);
  q.title = asString(row['title']);
  q.question = asString(row['question']);
  q.gist = asString(row['gist']);
  q.points = parsePoints(row['points']);
  q.bonus = asString(row['bonus']);
  q.redFlags = asString(row['redFlags']);
  q.fullAnswer = asString(row['fullAnswer']);
  const source = row['source'];
  if (source && typeof source === 'object') {
    const src = asRecord(source as Object);
    q.sourceLabel = asString(src['label']);
    q.sourceUrl = asString(src['url']);
  }
  const children = asObjectArray(row['children']);
  const nested: Question[] = [];
  for (let i = 0; i < children.length; i++) {
    nested.push(parseQuestion(children[i]));
  }
  q.children = nested;
  return q;
}

export function parseTopic(raw: Object): Topic {
  const row = asRecord(raw);
  const t = new Topic();
  t.id = asString(row['id']);
  t.index = asNumber(row['index']);
  t.bank = asString(row['bank'], 'alibaba');
  t.name = asString(row['name']);
  t.english = asString(row['english']);
  t.summary = asString(row['summary']);
  t.interviewerNote = asString(row['interviewerNote']);
  return t;
}

export class ParsedBank {
  topics: Topic[] = [];
  questions: Question[] = [];
  ailianIntro: AilianIntro = new AilianIntro();
  candidate: CandidateProfile | null = null;
  stats: BankStats = new BankStats();
}

export function parseBank(text: string): ParsedBank {
  const root = asRecord(JSON.parse(text) as Object);
  const err = asString(root['error']);
  if (err) {
    throw new Error(err);
  }
  const bank = new ParsedBank();
  const topicsRaw = asObjectArray(root['topics']);
  for (let i = 0; i < topicsRaw.length; i++) {
    bank.topics.push(parseTopic(topicsRaw[i]));
  }
  const questionsRaw = asObjectArray(root['questions']);
  for (let i = 0; i < questionsRaw.length; i++) {
    bank.questions.push(parseQuestion(questionsRaw[i]));
  }
  const introRaw = root['ailianIntro'];
  if (introRaw && typeof introRaw === 'object') {
    const intro = asRecord(introRaw as Object);
    bank.ailianIntro.candidate = asString(intro['candidate']);
    bank.ailianIntro.title = asString(intro['title']);
    bank.ailianIntro.body = asString(intro['body']);
  }
  const candRaw = root['candidate'];
  if (candRaw && typeof candRaw === 'object') {
    const cand = asRecord(candRaw as Object);
    const profile = new CandidateProfile();
    profile.name = asString(cand['name']);
    profile.from = asString(cand['from']);
    profile.to = asString(cand['to']);
    profile.oneLiner = asString(cand['oneLiner']);
    profile.interviewerFrame = asString(cand['interviewerFrame']);
    bank.candidate = profile;
  }
  const statsRaw = root['stats'];
  if (statsRaw && typeof statsRaw === 'object') {
    const stats = asRecord(statsRaw as Object);
    bank.stats.totalParents = asNumber(stats['totalParents']);
    bank.stats.totalQuestions = asNumber(stats['totalQuestions']);
    bank.stats.alibabaParents = asNumber(stats['alibabaParents']);
    bank.stats.ailianParents = asNumber(stats['ailianParents']);
    bank.stats.alibabaTopics = asNumber(stats['alibabaTopics']);
    bank.stats.ailianTopics = asNumber(stats['ailianTopics']);
  }
  if (bank.questions.length === 0 || bank.topics.length === 0) {
    throw new Error('题库接口返回的数据不完整。');
  }
  return bank;
}

export function parseJudge(text: string): JudgeResult {
  const root = asRecord(JSON.parse(text) as Object);
  const result = new JudgeResult();
  result.error = asString(root['error']);
  result.mode = asString(root['mode'], 'mock');
  result.model = asString(root['model']);
  result.score = asNumber(root['score']);
  result.verdict = asString(root['verdict'], '追问');
  result.summary = asString(root['summary']);
  result.nextAsk = asString(root['nextAsk']);
  result.betterOpening = asString(root['betterOpening']);
  const strengths = asObjectArray(root['strengths']);
  for (let i = 0; i < strengths.length; i++) {
    const s = asString(strengths[i]);
    if (s) {
      result.strengths.push(s);
    }
  }
  const gaps = asObjectArray(root['gaps']);
  for (let i = 0; i < gaps.length; i++) {
    const s = asString(gaps[i]);
    if (s) {
      result.gaps.push(s);
    }
  }
  const flags = asObjectArray(root['redFlagsHit']);
  for (let i = 0; i < flags.length; i++) {
    const s = asString(flags[i]);
    if (s) {
      result.redFlagsHit.push(s);
    }
  }
  return result;
}

export function parseLlmSettings(raw: string): LlmSettings {
  const settings = new LlmSettings();
  try {
    const row = asRecord(JSON.parse(raw) as Object);
    settings.provider = asString(row['provider'], 'qwen');
    settings.apiKey = asString(row['apiKey']);
    const preset = presetFor(settings.provider);
    const base = asString(row['baseUrl']).trim();
    settings.baseUrl = base ? base : (preset ? preset.baseUrl : settings.baseUrl);
    const model = asString(row['model']).trim();
    settings.model = model ? model : (preset ? preset.model : settings.model);
    settings.model = chatModelFor(settings);
    return settings;
  } catch (_e) {
    return settings;
  }
}

export function parseStringList(raw: string): string[] {
  try {
    const parsed = JSON.parse(raw) as Object;
    const list = asObjectArray(parsed);
    const out: string[] = [];
    for (let i = 0; i < list.length; i++) {
      const s = asString(list[i]);
      if (s) {
        out.push(s);
      }
    }
    return out;
  } catch (_e) {
    return [];
  }
}

export function parseAuthUser(raw: Object): AuthUser {
  const row = asRecord(raw);
  const user = new AuthUser();
  user.id = asString(row['id']);
  user.displayName = asString(row['displayName']);
  user.audience = asString(row['audience'], 'unset');
  user.status = asString(row['status'], 'active');
  user.isGuest = asBool(row['isGuest'], user.displayName === '访客' || !user.displayName);
  return user;
}

export function parseSession(text: string): SessionPayload {
  const root = asRecord(JSON.parse(text) as Object);
  const err = asString(root['error']);
  if (err) {
    throw new Error(err);
  }
  const payload = new SessionPayload();
  payload.token = asString(root['token']);
  const userRaw = root['user'];
  if (userRaw && typeof userRaw === 'object') {
    payload.user = parseAuthUser(userRaw as Object);
  }
  if (!payload.token || !payload.user.id) {
    throw new Error('登录返回不完整。');
  }
  return payload;
}

function parseHomeCard(raw: Object): HomeCard {
  const row = asRecord(raw);
  const card = new HomeCard();
  card.questionId = asString(row['questionId']);
  card.title = asString(row['title']);
  card.question = asString(row['question']);
  card.topicId = asString(row['topicId']);
  card.topicName = asString(row['topicName']);
  card.reason = asString(row['reason']);
  return card;
}

export function parseHome(text: string): HomePayload {
  const root = asRecord(JSON.parse(text) as Object);
  const err = asString(root['error']);
  if (err) {
    throw new Error(err);
  }
  const home = new HomePayload();
  home.audience = asString(root['audience'], 'unset');
  const pathRaw = root['path'];
  if (pathRaw && typeof pathRaw === 'object') {
    const path = asRecord(pathRaw as Object);
    home.pathName = asString(path['name']);
    home.pathSummary = asString(path['summary']);
  }
  const nextRaw = root['next'];
  if (nextRaw && typeof nextRaw === 'object') {
    home.next = parseHomeCard(nextRaw as Object);
  }
  const reviewRaw = asObjectArray(root['review']);
  for (let i = 0; i < reviewRaw.length; i++) {
    home.review.push(parseHomeCard(reviewRaw[i]));
  }
  const weakRaw = asObjectArray(root['weak']);
  for (let i = 0; i < weakRaw.length; i++) {
    home.weak.push(parseHomeCard(weakRaw[i]));
  }
  const statsRaw = root['stats'];
  if (statsRaw && typeof statsRaw === 'object') {
    const stats = asRecord(statsRaw as Object);
    home.mastered = asNumber(stats['mastered']);
    home.onPath = asNumber(stats['onPath']);
    home.doneOnPath = asNumber(stats['doneOnPath']);
  }
  return home;
}

export function parseMasteredPayload(text: string): string[] {
  const root = asRecord(JSON.parse(text) as Object);
  const err = asString(root['error']);
  if (err) {
    throw new Error(err);
  }
  const list = asObjectArray(root['mastered']);
  const out: string[] = [];
  for (let i = 0; i < list.length; i++) {
    const s = asString(list[i]);
    if (s) {
      out.push(s);
    }
  }
  return out;
}

export function parseResumeJob(raw: Object): ResumeJob {
  const row = asRecord(raw);
  const job = new ResumeJob();
  job.id = asString(row['id']);
  job.company = asString(row['company']);
  job.jobTitle = asString(row['jobTitle']);
  job.startedOn = asString(row['startedOn']);
  job.endedOn = asString(row['endedOn']);
  job.isCurrent = asBool(row['isCurrent']);
  job.summary = asString(row['summary']);
  job.sortOrder = asNumber(row['sortOrder']);
  return job;
}

export function parseResumeProject(raw: Object): ResumeProject {
  const row = asRecord(raw);
  const project = new ResumeProject();
  project.id = asString(row['id']);
  project.jobId = asString(row['jobId']);
  project.name = asString(row['name']);
  project.company = asString(row['company']);
  project.jobRole = asString(row['jobRole']);
  project.startedOn = asString(row['startedOn']);
  project.endedOn = asString(row['endedOn']);
  project.techStack = asStringArray(row['techStack']);
  project.responsibilities = asString(row['responsibilities']);
  project.outcomes = asString(row['outcomes']);
  project.sortOrder = asNumber(row['sortOrder']);
  return project;
}

export function parseResumeProfile(raw: Object): ResumeProfile {
  const row = asRecord(raw);
  const profile = new ResumeProfile();
  profile.fullName = asString(row['fullName']);
  profile.yearsExperience = asNumber(row['yearsExperience']);
  profile.currentTitle = asString(row['currentTitle']);
  profile.targetTitle = asString(row['targetTitle']);
  profile.summary = asString(row['summary']);
  profile.skills = asStringArray(row['skills']);
  profile.confirmedAt = asString(row['confirmedAt']);
  return profile;
}

export function parseResumeArchive(raw: Object): ResumeArchive {
  const row = asRecord(raw);
  const err = asString(row['error']);
  if (err) {
    throw new Error(err);
  }
  const archive = new ResumeArchive();
  archive.id = asString(row['id']);
  archive.fileName = asString(row['fileName']);
  archive.parseStatus = asString(row['parseStatus']);
  archive.parseError = asString(row['parseError']);
  archive.isActive = asBool(row['isActive']);
  archive.confirmedAt = asString(row['confirmedAt']);
  archive.updatedAt = asString(row['updatedAt']);
  const profileRaw = row['profile'];
  if (profileRaw && typeof profileRaw === 'object') {
    archive.profile = parseResumeProfile(profileRaw as Object);
  }
  const jobsRaw = asObjectArray(row['jobs']);
  for (let i = 0; i < jobsRaw.length; i++) {
    archive.jobs.push(parseResumeJob(jobsRaw[i]));
  }
  const projectsRaw = asObjectArray(row['projects']);
  for (let i = 0; i < projectsRaw.length; i++) {
    archive.projects.push(parseResumeProject(projectsRaw[i]));
  }
  return archive;
}

export class ParsedResumeList {
  items: ResumeArchive[] = [];
  activeId: string = '';
}

export function parseResumeList(raw: Object): ParsedResumeList {
  const root = asRecord(raw);
  const err = asString(root['error']);
  if (err) {
    throw new Error(err);
  }
  const parsed = new ParsedResumeList();
  parsed.activeId = asString(root['activeId']);
  const itemsRaw = asObjectArray(root['items']);
  for (let i = 0; i < itemsRaw.length; i++) {
    parsed.items.push(parseResumeArchive(itemsRaw[i]));
  }
  return parsed;
}

export function parseMockTurn(raw: Object): MockTurn {
  const root = asRecord(raw);
  const err = asString(root['error']);
  if (err) {
    throw new Error(err);
  }
  const turn = new MockTurn();
  turn.itemKind = asString(root['itemKind']);
  turn.resumeQuestionId = asString(root['resumeQuestionId']);
  turn.questionId = asString(root['questionId']);
  const questionRaw = root['question'];
  if (questionRaw && typeof questionRaw === 'object') {
    const question = asRecord(questionRaw as Object);
    turn.question = asString(question['question']);
    turn.gist = asString(question['gist']);
    turn.points = parsePoints(question['points']);
    turn.angle = asString(question['angle']);
  }
  const progressRaw = root['progress'];
  if (progressRaw && typeof progressRaw === 'object') {
    const progress = asRecord(progressRaw as Object);
    turn.phase = asString(progress['phase']);
    turn.projectIndex = asNumber(progress['projectIndex']);
    turn.projectCount = asNumber(progress['projectCount']);
    turn.questionInProject = asNumber(progress['questionInProject']);
  }
  return turn;
}
