@Observed
export class AnswerBlock {
  heading: string = '';
  body: string = '';
}

@Observed
export class Topic {
  id: string = '';
  index: number = 0;
  bank: string = 'alibaba';
  name: string = '';
  english: string = '';
  summary: string = '';
  interviewerNote: string = '';
}

@Observed
export class Question {
  id: string = '';
  parentId: string = '';
  prerequisiteId: string = '';
  level: number = 1;
  topicId: string = '';
  difficulty: string = '基础';
  angle: string = '';
  title: string = '';
  question: string = '';
  gist: string = '';
  points: AnswerBlock[] = [];
  bonus: string = '';
  redFlags: string = '';
  sourceLabel: string = '';
  sourceUrl: string = '';
  fullAnswer: string = '';
  children: Question[] = [];
}

@Observed
export class AilianIntro {
  candidate: string = '';
  title: string = '';
  body: string = '';
}

@Observed
export class CandidateProfile {
  name: string = '';
  from: string = '';
  to: string = '';
  oneLiner: string = '';
  interviewerFrame: string = '';
}

@Observed
export class BankStats {
  totalParents: number = 0;
  totalQuestions: number = 0;
  alibabaParents: number = 0;
  ailianParents: number = 0;
  alibabaTopics: number = 0;
  ailianTopics: number = 0;
}

export class JudgeResult {
  mode: string = 'mock';
  model: string = '';
  score: number = 0;
  verdict: string = '追问';
  summary: string = '';
  strengths: string[] = [];
  gaps: string[] = [];
  redFlagsHit: string[] = [];
  nextAsk: string = '';
  betterOpening: string = '';
  error: string = '';
}

export class LlmSettings {
  provider: string = 'qwen';
  apiKey: string = '';
  baseUrl: string = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  model: string = 'qwen-plus';
}

export interface ProviderPreset {
  id: string;
  label: string;
  baseUrl: string;
  model: string;
  hint: string;
}

export const QWEN_PRESET: ProviderPreset = {
  id: 'qwen',
  label: '通义千问',
  baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
  model: 'qwen-plus',
  hint: '阿里云百炼 API-KEY。点评模型填 qwen-plus。听写和朗读会自动走语音模型。'
};

export const DEEPSEEK_PRESET: ProviderPreset = {
  id: 'deepseek',
  label: 'DeepSeek',
  baseUrl: 'https://api.deepseek.com',
  model: 'deepseek-chat',
  hint: 'DeepSeek 不支持语音。听写请用系统听写，或改通义。'
};

export const OPENAI_PRESET: ProviderPreset = {
  id: 'openai',
  label: 'OpenAI',
  baseUrl: 'https://api.openai.com/v1',
  model: 'gpt-4o-mini',
  hint: '官方 OpenAI 或任意 /v1 兼容网关。'
};

export function presetFor(provider: string): ProviderPreset | null {
  if (provider === 'qwen') {
    return QWEN_PRESET;
  }
  if (provider === 'deepseek') {
    return DEEPSEEK_PRESET;
  }
  if (provider === 'openai') {
    return OPENAI_PRESET;
  }
  return null;
}

export function looksLikeSpeechModel(model: string): boolean {
  return /(?:^|[-_/])(?:tts|asr|whisper)(?:$|[-_/])/i.test(model) || /speech/i.test(model);
}

export function chatModelFor(settings: LlmSettings): string {
  if (!looksLikeSpeechModel(settings.model)) {
    return settings.model;
  }
  if (settings.provider === 'qwen' || /dashscope/i.test(settings.baseUrl)) {
    return QWEN_PRESET.model;
  }
  if (settings.provider === 'openai') {
    return OPENAI_PRESET.model;
  }
  return settings.model;
}

export const DIFFICULTIES: string[] = ['全部', '基础', '进阶', '场景', '深挖', '系统设计'];

@Observed
export class AuthUser {
  id: string = '';
  displayName: string = '';
  audience: string = 'unset';
  status: string = 'active';
  isGuest: boolean = true;
}

export class SessionPayload {
  token: string = '';
  user: AuthUser = new AuthUser();
}

@Observed
export class HomeCard {
  questionId: string = '';
  title: string = '';
  question: string = '';
  topicId: string = '';
  topicName: string = '';
  reason: string = '';
}

@Observed
export class HomePayload {
  audience: string = 'unset';
  pathName: string = '';
  pathSummary: string = '';
  next: HomeCard | null = null;
  review: HomeCard[] = [];
  weak: HomeCard[] = [];
  mastered: number = 0;
  onPath: number = 0;
  doneOnPath: number = 0;
}

@Observed
export class ResumeJob {
  id: string = '';
  company: string = '';
  jobTitle: string = '';
  startedOn: string = '';
  endedOn: string = '';
  isCurrent: boolean = false;
  summary: string = '';
  sortOrder: number = 0;
}

@Observed
export class ResumeProject {
  id: string = '';
  jobId: string = '';
  name: string = '';
  company: string = '';
  jobRole: string = '';
  startedOn: string = '';
  endedOn: string = '';
  techStack: string[] = [];
  responsibilities: string = '';
  outcomes: string = '';
  sortOrder: number = 0;
}

@Observed
export class ResumeProfile {
  fullName: string = '';
  yearsExperience: number = 0;
  currentTitle: string = '';
  targetTitle: string = '';
  summary: string = '';
  skills: string[] = [];
  confirmedAt: string = '';
}

@Observed
export class ResumeArchive {
  id: string = '';
  fileName: string = '';
  parseStatus: string = '';
  parseError: string = '';
  isActive: boolean = false;
  confirmedAt: string = '';
  updatedAt: string = '';
  profile: ResumeProfile = new ResumeProfile();
  jobs: ResumeJob[] = [];
  projects: ResumeProject[] = [];
}

export class MockTurn {
  itemKind: string = '';
  resumeQuestionId: string = '';
  questionId: string = '';
  question: string = '';
  gist: string = '';
  points: AnswerBlock[] = [];
  angle: string = '';
  phase: string = '';
  projectIndex: number = 0;
  projectCount: number = 0;
  questionInProject: number = 0;
}
