import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { Theme } from '../common/AppConfig';
import { AppContextHolder } from '../common/AppContextHolder';
import { asNumber, asRecord, asString, errorMessage } from '../common/JsonUtil';
import { ResumeArchive, ResumeJob, ResumeProject } from '../model/Types';
import { ResumeStore } from '../store/ResumeStore';

const DOCX_MIME: string = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

@Component
export struct ResumeArchivePane {
  @State tick: number = 0;
  @State skillsText: string = '';
  @State yearsText: string = '';
  private draftStamp: string = '';
  private unsub: () => void = () => {
  };

  aboutToAppear(): void {
    this.unsub = ResumeStore.subscribe(() => {
      this.syncDrafts();
      this.tick++;
    });
    this.syncDrafts();
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  private syncDrafts(): void {
    const archive = ResumeStore.archive;
    const stamp = archive ? `${archive.id}|${archive.parseStatus}|${archive.updatedAt}` : '';
    if (stamp === this.draftStamp) {
      return;
    }
    this.draftStamp = stamp;
    if (!archive) {
      this.skillsText = '';
      this.yearsText = '';
      return;
    }
    this.skillsText = joinComma(archive.profile.skills);
    this.yearsText = `${archive.profile.yearsExperience}`;
  }

  private statusText(): string {
    if (ResumeStore.error) {
      return ResumeStore.error;
    }
    const archive = ResumeStore.archive;
    if (archive && archive.parseError) {
      return archive.parseError;
    }
    return '';
  }

  private async pickDocument(): Promise<void> {
    const ctx = AppContextHolder.context;
    if (!ctx) {
      ResumeStore.error = '无法访问应用上下文，请重启后再选文件。';
      ResumeStore.emit();
      return;
    }
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.pdf', '.docx', '.jpg', '.jpeg', '.png', '.webp'];
      const viewPicker = new picker.DocumentViewPicker(ctx);
      const uris: Array<string> = await viewPicker.select(options);
      if (!uris || uris.length === 0) {
        return;
      }
      await this.ingestUri(uris[0], '');
    } catch (e) {
      this.onPickerFail(e as Object);
    }
  }

  private async pickPhoto(): Promise<void> {
    const ctx = AppContextHolder.context;
    if (!ctx) {
      ResumeStore.error = '无法访问应用上下文，请重启后再选文件。';
      ResumeStore.emit();
      return;
    }
    try {
      const options = new picker.PhotoSelectOptions();
      options.maxSelectNumber = 1;
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      const viewPicker = new picker.PhotoViewPicker(ctx);
      const result: picker.PhotoSelectResult = await viewPicker.select(options);
      if (!result || !result.photoUris || result.photoUris.length === 0) {
        return;
      }
      await this.ingestUri(result.photoUris[0], '.jpg');
    } catch (e) {
      this.onPickerFail(e as Object);
    }
  }

  private onPickerFail(e: Object): void {
    if (isPickerCancel(e)) {
      return;
    }
    ResumeStore.error = pickerErrorText(e);
    ResumeStore.emit();
  }

  private async ingestUri(uri: string, fallbackExt: string): Promise<void> {
    const ctx = AppContextHolder.context;
    if (!ctx) {
      ResumeStore.error = '无法访问应用上下文，请重启后再选文件。';
      ResumeStore.emit();
      return;
    }
    const fileName = nameFromUri(uri, fallbackExt);
    const mime = mimeFromName(fileName);
    const destPath = `${ctx.cacheDir}/${fileName}`;
    try {
      await copyPickerUri(uri, destPath);
    } catch (e) {
      ResumeStore.error = pickerErrorText(e as Object);
      ResumeStore.emit();
      return;
    }
    ResumeStore.archive = null;
    ResumeStore.selectedProjectId = '';
    await ResumeStore.upload(destPath, mime, fileName);
  }

  private reupload(): void {
    ResumeStore.clear();
    void this.pickDocument();
  }

  private async confirmArchive(): Promise<void> {
    try {
      await ResumeStore.saveAndConfirm();
    } catch (_e) {
    }
  }

  private addJob(): void {
    const archive = ResumeStore.archive;
    if (!archive) {
      return;
    }
    const job = new ResumeJob();
    job.id = `job-${Date.now()}-${archive.jobs.length}`;
    job.sortOrder = archive.jobs.length;
    const jobs = archive.jobs.slice();
    jobs.push(job);
    archive.jobs = jobs;
    ResumeStore.emit();
  }

  private removeJob(job: ResumeJob): void {
    const archive = ResumeStore.archive;
    if (!archive) {
      return;
    }
    const jobs: ResumeJob[] = [];
    for (let i = 0; i < archive.jobs.length; i++) {
      if (archive.jobs[i] !== job) {
        jobs.push(archive.jobs[i]);
      }
    }
    archive.jobs = jobs;
    ResumeStore.emit();
  }

  private addProject(): void {
    const archive = ResumeStore.archive;
    if (!archive) {
      return;
    }
    const project = new ResumeProject();
    project.id = `project-${Date.now()}-${archive.projects.length}`;
    if (archive.jobs.length > 0) {
      project.jobId = archive.jobs[0].id;
    }
    project.sortOrder = archive.projects.length;
    const projects = archive.projects.slice();
    projects.push(project);
    archive.projects = projects;
    ResumeStore.emit();
  }

  private removeProject(project: ResumeProject): void {
    const archive = ResumeStore.archive;
    if (!archive) {
      return;
    }
    const projects: ResumeProject[] = [];
    for (let i = 0; i < archive.projects.length; i++) {
      if (archive.projects[i] !== project) {
        projects.push(archive.projects[i]);
      }
    }
    archive.projects = projects;
    ResumeStore.emit();
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('简历档案').fontSize(12).fontColor(Theme.accent)
        Text('上传 PDF、Word 或图片，抽出后可改再确认。')
          .fontSize(15)
          .lineHeight(24)
          .fontColor(Theme.muted)
        Button('选择 PDF / Word / 图片')
          .backgroundColor(Theme.accent)
          .enabled(!ResumeStore.parsing)
          .onClick(() => {
            void this.pickDocument();
          })
        Button('从相册选图')
          .backgroundColor(Theme.card)
          .fontColor(Theme.ink)
          .enabled(!ResumeStore.parsing)
          .onClick(() => {
            void this.pickPhoto();
          })
        if (ResumeStore.parsing) {
          Row({ space: 8 }) {
            LoadingProgress().color(Theme.accent).width(28)
            Text('正在抽出档案…').fontSize(14).fontColor(Theme.muted)
          }
        }
        if (this.statusText()) {
          Text(this.statusText())
            .fontSize(14)
            .lineHeight(22)
            .fontColor(Theme.danger)
        }
        if (ResumeStore.archive && !ResumeStore.parsing) {
          this.Editor(ResumeStore.archive)
        }
      }
      .width('100%')
      .padding(24)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.paper)
    .scrollBar(BarState.Off)
  }

  @Builder
  Editor(archive: ResumeArchive) {
    Column({ space: 12 }) {
      if (archive.fileName) {
        Text(archive.fileName).fontSize(12).fontColor(Theme.muted)
      }
      Text('姓名').fontSize(12).fontColor(Theme.muted)
      TextInput({ placeholder: '姓名', text: archive.profile.fullName })
        .width('100%')
        .backgroundColor(Theme.card)
        .onChange((v: string) => {
          archive.profile.fullName = v;
          ResumeStore.emit();
        })
      Text('年限').fontSize(12).fontColor(Theme.muted)
      TextInput({ placeholder: '年限', text: this.yearsText })
        .width('100%')
        .type(InputType.Number)
        .backgroundColor(Theme.card)
        .onChange((v: string) => {
          this.yearsText = v;
          const n = Number(v);
          archive.profile.yearsExperience = Number.isFinite(n) ? n : 0;
          ResumeStore.emit();
        })
      Text('当前岗位').fontSize(12).fontColor(Theme.muted)
      TextInput({ placeholder: '当前岗位', text: archive.profile.currentTitle })
        .width('100%')
        .backgroundColor(Theme.card)
        .onChange((v: string) => {
          archive.profile.currentTitle = v;
          ResumeStore.emit();
        })
      Text('目标岗位').fontSize(12).fontColor(Theme.muted)
      TextInput({ placeholder: '目标岗位', text: archive.profile.targetTitle })
        .width('100%')
        .backgroundColor(Theme.card)
        .onChange((v: string) => {
          archive.profile.targetTitle = v;
          ResumeStore.emit();
        })
      Text('技能（逗号分隔）').fontSize(12).fontColor(Theme.muted)
      TextInput({ placeholder: 'Java, Agent, 面试', text: this.skillsText })
        .width('100%')
        .backgroundColor(Theme.card)
        .onChange((v: string) => {
          this.skillsText = v;
          archive.profile.skills = splitComma(v);
          ResumeStore.emit();
        })
      Text('简介').fontSize(12).fontColor(Theme.muted)
      TextArea({ placeholder: '一段话介绍自己', text: archive.profile.summary })
        .width('100%')
        .height(96)
        .backgroundColor(Theme.card)
        .onChange((v: string) => {
          archive.profile.summary = v;
          ResumeStore.emit();
        })

      Text('工作经历').fontSize(16).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
      ForEach(archive.jobs, (job: ResumeJob, index: number) => {
        Column({ space: 8 }) {
          TextInput({ placeholder: '公司', text: job.company })
            .width('100%')
            .backgroundColor(Theme.card)
            .onChange((v: string) => {
              job.company = v;
              ResumeStore.emit();
            })
          TextInput({ placeholder: '岗位', text: job.jobTitle })
            .width('100%')
            .backgroundColor(Theme.card)
            .onChange((v: string) => {
              job.jobTitle = v;
              ResumeStore.emit();
            })
          TextArea({ placeholder: '这段经历做什么', text: job.summary })
            .width('100%')
            .height(72)
            .backgroundColor(Theme.card)
            .onChange((v: string) => {
              job.summary = v;
              ResumeStore.emit();
            })
          Button('删除这段经历')
            .backgroundColor(Theme.card)
            .fontColor(Theme.danger)
            .onClick(() => this.removeJob(job))
        }
        .width('100%')
      }, (job: ResumeJob, index: number) => `${job.id}-${index}`)
      Button('增加一段经历')
        .backgroundColor(Theme.card)
        .fontColor(Theme.ink)
        .onClick(() => this.addJob())

      Text('项目').fontSize(16).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
      ForEach(archive.projects, (project: ResumeProject, index: number) => {
        Column({ space: 8 }) {
          TextInput({ placeholder: '项目名', text: project.name })
            .width('100%')
            .backgroundColor(Theme.card)
            .onChange((v: string) => {
              project.name = v;
              ResumeStore.emit();
            })
          TextInput({ placeholder: '公司', text: project.company })
            .width('100%')
            .backgroundColor(Theme.card)
            .onChange((v: string) => {
              project.company = v;
              ResumeStore.emit();
            })
          TextArea({ placeholder: '职责', text: project.responsibilities })
            .width('100%')
            .height(72)
            .backgroundColor(Theme.card)
            .onChange((v: string) => {
              project.responsibilities = v;
              ResumeStore.emit();
            })
          TextArea({ placeholder: '结果 / 量化', text: project.outcomes })
            .width('100%')
            .height(72)
            .backgroundColor(Theme.card)
            .onChange((v: string) => {
              project.outcomes = v;
              ResumeStore.emit();
            })
          TextInput({ placeholder: '技术栈，逗号分隔', text: joinComma(project.techStack) })
            .width('100%')
            .backgroundColor(Theme.card)
            .onChange((v: string) => {
              project.techStack = splitComma(v);
              ResumeStore.emit();
            })
          Button('删除这个项目')
            .backgroundColor(Theme.card)
            .fontColor(Theme.danger)
            .onClick(() => this.removeProject(project))
        }
        .width('100%')
      }, (project: ResumeProject, index: number) => `${project.id}-${index}`)
      Button('增加项目')
        .backgroundColor(Theme.card)
        .fontColor(Theme.ink)
        .onClick(() => this.addProject())

      Button('确认这份档案')
        .backgroundColor(Theme.accent)
        .enabled(!ResumeStore.parsing)
        .onClick(() => {
          void this.confirmArchive();
        })
      Button('重新上传')
        .backgroundColor(Theme.card)
        .fontColor(Theme.ink)
        .enabled(!ResumeStore.parsing)
        .onClick(() => this.reupload())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

function joinComma(items: string[]): string {
  return items.join(', ');
}

function splitComma(raw: string): string[] {
  const parts = raw.split(',');
  const out: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const s = parts[i].trim();
    if (s.length > 0) {
      out.push(s);
    }
  }
  return out;
}

function nameFromUri(uri: string, fallbackExt: string): string {
  let path = uri;
  try {
    path = decodeURIComponent(uri);
  } catch (_e) {
  }
  const q = path.indexOf('?');
  if (q >= 0) {
    path = path.substring(0, q);
  }
  const slash = path.lastIndexOf('/');
  let name = slash >= 0 ? path.substring(slash + 1) : path;
  name = name.replace(/[\\/:*?"<>|]/g, '_');
  if (!name) {
    name = `resume-${Date.now()}${fallbackExt ? fallbackExt : '.bin'}`;
  }
  if (name.lastIndexOf('.') < 0) {
    name = `${name}${fallbackExt ? fallbackExt : ''}`;
  }
  return name;
}

function mimeFromName(fileName: string): string {
  const lower = fileName.toLowerCase();
  const dot = lower.lastIndexOf('.');
  const ext = dot >= 0 ? lower.substring(dot) : '';
  if (ext === '.pdf') {
    return 'application/pdf';
  }
  if (ext === '.docx') {
    return DOCX_MIME;
  }
  if (ext === '.jpg' || ext === '.jpeg') {
    return 'image/jpeg';
  }
  if (ext === '.png') {
    return 'image/png';
  }
  if (ext === '.webp') {
    return 'image/webp';
  }
  return 'application/octet-stream';
}

async function copyPickerUri(uri: string, destPath: string): Promise<void> {
  const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const destFile = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      await fs.copyFile(srcFile.fd, destFile.fd);
    } finally {
      fs.closeSync(destFile);
    }
  } finally {
    fs.closeSync(srcFile);
  }
}

function isPickerCancel(e: Object): boolean {
  const code = asNumber(asRecord(e)['code']);
  return code === 13900004 || code === 13900001;
}

function pickerErrorText(e: Object): string {
  const rec = asRecord(e);
  const msg = asString(rec['message']);
  if (msg) {
    return msg;
  }
  return errorMessage(e);
}
