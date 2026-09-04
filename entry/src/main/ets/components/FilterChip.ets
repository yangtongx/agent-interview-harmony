import { Theme } from '../common/AppConfig';

@Component
export struct FilterChip {
  @Prop label: string = '';
  @Prop active: boolean = false;
  onSelect: () => void = () => {
  };

  build() {
    Text(this.label)
      .fontSize(12)
      .fontColor(this.active ? Color.White : Theme.ink)
      .backgroundColor(this.active ? Theme.accent : Theme.card)
      .border({
        width: this.active ? 0 : 1,
        color: Theme.line
      })
      .padding({
        left: 10,
        right: 10,
        top: 6,
        bottom: 6
      })
      .borderRadius(999)
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.onSelect();
      })
  }
}

@Component
export struct DiffBadge {
  @Prop difficulty: string = '';

  private color(): string {
    if (this.difficulty === '基础') {
      return '#0F7A5A';
    }
    if (this.difficulty === '进阶') {
      return '#0369A1';
    }
    if (this.difficulty === '场景') {
      return '#B45309';
    }
    if (this.difficulty === '深挖') {
      return '#6D28D9';
    }
    return Theme.accent;
  }

  build() {
    Text(this.difficulty)
      .fontSize(11)
      .fontColor(this.color())
      .backgroundColor('#FFFDF8')
      .border({ width: 1, color: this.color() })
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .borderRadius(999)
  }
}
