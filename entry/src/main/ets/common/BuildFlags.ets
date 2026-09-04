import BuildProfile from 'BuildProfile';

export class BuildFlags {
  static allowCleartext(): boolean {
    if (BuildProfile.DEBUG === true) {
      return true;
    }
    if (BuildProfile.BUILD_MODE_NAME === 'debug') {
      return true;
    }
    return false;
  }
}
