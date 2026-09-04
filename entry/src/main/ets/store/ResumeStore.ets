import { asRecord, asString, errorMessage } from '../common/JsonUtil';
import { Emitter } from '../common/Emitter';
import { parseResumeArchive, parseResumeList } from '../model/Parse';
import { ResumeArchive, ResumeJob, ResumeProject } from '../model/Types';
import { ApiClient } from '../network/ApiClient';

export class ResumeStore {
  static archive: ResumeArchive | null = null;
  static loading: boolean = false;
  static parsing: boolean = false;
  static error: string = '';
  static selectedProjectId: string = '';
  private static bus: Emitter = new Emitter();
  private static pollGeneration: number = 0;

  static subscribe(fn: () => void): () => void {
    return ResumeStore.bus.subscribe(fn);
  }

  static emit(): void {
    ResumeStore.bus.emit();
  }

  static cancelPoll(): void {
    ResumeStore.pollGeneration++;
    ResumeStore.parsing = false;
  }

  static hasConfirmed(): boolean {
    return ResumeStore.archive !== null && ResumeStore.archive.confirmedAt.trim().length > 0;
  }

  static clear(): void {
    ResumeStore.cancelPoll();
    ResumeStore.archive = null;
    ResumeStore.error = '';
    ResumeStore.parsing = false;
    ResumeStore.selectedProjectId = '';
    ResumeStore.emit();
  }

  static async refresh(): Promise<void> {
    ResumeStore.loading = true;
    ResumeStore.error = '';
    ResumeStore.emit();
    try {
      const list = parseResumeList(JSON.parse(await ApiClient.getResumes()) as Object);
      let id = list.activeId;
      if (!id && list.items.length > 0) {
        id = list.items[0].id;
      }
      if (id) {
        ResumeStore.archive = parseResumeArchive(JSON.parse(await ApiClient.getResume(id)) as Object);
      } else {
        ResumeStore.archive = null;
      }
      ResumeStore.syncSelectedProject();
      ResumeStore.loading = false;
      ResumeStore.emit();
    } catch (e) {
      ResumeStore.error = errorMessage(e as Object);
      ResumeStore.loading = false;
      ResumeStore.emit();
    }
  }

  static async upload(filePath: string, mime: string, fileName: string): Promise<void> {
    ResumeStore.cancelPoll();
    ResumeStore.parsing = true;
    ResumeStore.error = '';
    ResumeStore.emit();
    try {
      const text = await ApiClient.uploadResume(filePath, mime, fileName);
      const id = asString(asRecord(JSON.parse(text) as Object)['id']);
      if (!id) {
        throw new Error('上传未返回简历编号。');
      }
      await ResumeStore.poll(id);
    } catch (e) {
      ResumeStore.parsing = false;
      ResumeStore.error = errorMessage(e as Object);
      ResumeStore.emit();
    }
  }

  static async poll(id: string): Promise<void> {
    const gen = ++ResumeStore.pollGeneration;
    const started = Date.now();
    while (Date.now() - started < 90000) {
      if (gen !== ResumeStore.pollGeneration) {
        return;
      }
      const row = parseResumeArchive(JSON.parse(await ApiClient.getResume(id)) as Object);
      ResumeStore.archive = row;
      ResumeStore.syncSelectedProject();
      ResumeStore.emit();
      if (row.parseStatus === 'parsed' || row.parseStatus === 'needs_review' || row.parseStatus === 'failed') {
        ResumeStore.parsing = false;
        ResumeStore.emit();
        return;
      }
      await sleep(1500);
    }
    if (gen !== ResumeStore.pollGeneration) {
      return;
    }
    ResumeStore.parsing = false;
    ResumeStore.error = '解析超时，请改档案或重传';
    ResumeStore.emit();
  }

  static async saveAndConfirm(): Promise<void> {
    const archive = ResumeStore.archive;
    if (!archive) {
      throw new Error('没有可确认的档案。');
    }
    if (!ResumeStore.hasValidProject(archive)) {
      ResumeStore.error = '至少保留一个项目，并填写项目名和职责。';
      ResumeStore.emit();
      throw new Error(ResumeStore.error);
    }
    try {
      await ApiClient.putResume(archive.id, ResumeStore.putBody(archive));
      const confirmText = await ApiClient.confirmResume(archive.id);
      ResumeStore.archive = await ResumeStore.parseConfirmOrReload(confirmText, archive.id);
      ResumeStore.syncSelectedProject();
      ResumeStore.error = '';
      ResumeStore.emit();
    } catch (e) {
      ResumeStore.error = errorMessage(e as Object);
      ResumeStore.emit();
      throw new Error(ResumeStore.error);
    }
  }

  private static hasValidProject(archive: ResumeArchive): boolean {
    if (archive.projects.length < 1) {
      return false;
    }
    for (let i = 0; i < archive.projects.length; i++) {
      const project = archive.projects[i];
      if (project.name.trim().length === 0 || project.responsibilities.trim().length === 0) {
        return false;
      }
    }
    return true;
  }

  private static putBody(archive: ResumeArchive): Record<string, Object> {
    const profile = archive.profile;
    const jobs: Object[] = [];
    for (let i = 0; i < archive.jobs.length; i++) {
      jobs.push(ResumeStore.jobBody(archive.jobs[i]));
    }
    const projects: Object[] = [];
    for (let i = 0; i < archive.projects.length; i++) {
      projects.push(ResumeStore.projectBody(archive.projects[i]));
    }
    const profileBody: Record<string, Object> = {
      'fullName': profile.fullName,
      'yearsExperience': profile.yearsExperience,
      'currentTitle': profile.currentTitle,
      'targetTitle': profile.targetTitle,
      'summary': profile.summary,
      'skills': profile.skills
    };
    return {
      'profile': profileBody,
      'jobs': jobs,
      'projects': projects
    };
  }

  private static jobBody(job: ResumeJob): Record<string, Object> {
    return {
      'id': job.id,
      'company': job.company,
      'jobTitle': job.jobTitle,
      'startedOn': job.startedOn,
      'endedOn': job.endedOn,
      'isCurrent': job.isCurrent,
      'summary': job.summary,
      'sortOrder': job.sortOrder
    };
  }

  private static projectBody(project: ResumeProject): Record<string, Object> {
    return {
      'jobId': project.jobId,
      'name': project.name,
      'company': project.company,
      'jobRole': project.jobRole,
      'startedOn': project.startedOn,
      'endedOn': project.endedOn,
      'techStack': project.techStack,
      'responsibilities': project.responsibilities,
      'outcomes': project.outcomes,
      'sortOrder': project.sortOrder
    };
  }

  private static async parseConfirmOrReload(confirmText: string, id: string): Promise<ResumeArchive> {
    try {
      const row = parseResumeArchive(JSON.parse(confirmText) as Object);
      if (row.id) {
        return row;
      }
    } catch (_e) {
    }
    return parseResumeArchive(JSON.parse(await ApiClient.getResume(id)) as Object);
  }

  private static syncSelectedProject(): void {
    const archive = ResumeStore.archive;
    if (!archive || archive.projects.length === 0) {
      ResumeStore.selectedProjectId = '';
      return;
    }
    for (let i = 0; i < archive.projects.length; i++) {
      if (archive.projects[i].id === ResumeStore.selectedProjectId) {
        return;
      }
    }
    ResumeStore.selectedProjectId = archive.projects[0].id;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}
