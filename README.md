# Official GitHub-hosted Android CI comparison

This benchmark builds Google's Android Architecture Samples and runs its 38
unchanged instrumentation tests on a standard GitHub-hosted Ubuntu 24.04 runner.
The exact upstream commit and source hashes are recorded in `UPSTREAM.json`.
Original licensing is retained. No private backend or SDK implementation,
credentials, AWS access configuration, or earlier Git history is included.

The workflow is manual only, limited to 30 minutes, and uses read-only repository
permissions. It runs one fresh API 35 Google APIs x86_64 AVD with two Android
cores, 4 GiB Android RAM, the pinned emulator and Action, two Gradle workers, and
a private empty Gradle home. JUnit must match all 38 upstream cases without
failures or skips. Failed samples and diagnostic artifacts are retained.

The measurement harness is shared with the comparison workload. The platform
memory check records GitHub's native backing instead of requiring the explicit
huge-page reservation used by the Celesto staging environment. It does not
disable kernel mitigations or change GitHub's memory policy. KVM access, if
needed, is granted only to the job user through a device ACL.

The first attempt booted Android but failed the subsequent KVM permission guard
before compiling the app. It is retained as a failed setup sample. Access is now
recorded and checked at initial setup, immediately before emulator launch, and
at workload entry; only the same job user's device ACL may be restored. The
strict permission check and actual unprivileged KVM API probe must both pass.
Package inventory reads known metadata locations rather than recursively
walking large, unrelated SDK/NDK trees. Whole-VM CPU ticks are sampled separately
from waited-child CPU, which does not capture Gradle daemon work completely.

Report GitHub assignment wait, tool normalization/setup, Android boot/readiness,
APK build, install/launch, instrumentation, artifact upload, and whole-job time.
Actual CPU model, resources, image version, JDK/SDK revisions, memory, swap and
filesystem samples are retained. GitHub's VM provisioning time is not directly
observable; assignment wait must not be presented as hypervisor boot time.

Public and private standard runners have different resource allocations. Record
repository visibility and actual runtime hardware before interpreting results.
Single samples do not establish a production latency percentile or SLA.
