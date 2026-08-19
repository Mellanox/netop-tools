## Description: <br>
Create or update a SECURITY.md file following NVIDIA security documentation standards, analyzing the repository codebase for languages, frameworks, dependencies, APIs, network exposure, data handling, and auth mechanisms, then generating a contextually rich SECURITY.md with Reporting Policy, Architecture Context, Threat Model, and Critical Security Assumptions. <br>

This skill is ready for commercial/non-commercial use. <br>

## Owner
NVIDIA <br>

### License/Terms of Use: <br>
## Use Case: <br>
Developers and security engineers use this skill to generate standardized SECURITY.md documentation for repositories, ensuring consistent vulnerability disclosure policies, architecture context, threat models, and critical security assumptions. <br>

### Deployment Geography for Use: <br>
Global <br>

## Requirements / Dependencies: <br>
**Requires API Key or External Credential:** [Not Specified] <br>
**Credential Type(s):** [None identified] <br>  

Do not include secrets in prompts/logs/output; use least-privilege credentials; rotate keys as appropriate. <br>

## Known Risks and Mitigations: <br>
Risk: Review before execution as proposals could introduce incorrect or misleading guidance into skills. <br>
Mitigation: Review and scan skill before deployment. <br>

## Reference(s): <br>
- [Security MD Template](references/security-md-template.md) <br>
- [Repository Exposure Classification](references/repository-exposure-classification.md) <br>
- [Service Exposure Classification](references/service-exposure-classification.md) <br>
- [Triage File Reference](references/triage-file-reference.md) <br>
- [NemoClaw Example](references/examples/nemoclaw-example.md) <br>
- [OpenClaw Example](references/examples/openclaw-example.md) <br>


## Skill Output: <br>
**Output Type(s):** [Files, Analysis] <br>
**Output Format:** [Markdown (SECURITY.md and optional .security-triage.yaml)] <br>
**Output Parameters:** [1D] <br>
**Other Properties Related to Output:** [None] <br>

## Evaluation Metrics Used: <br>
Reported benchmark dimensions: <br>
- Security: Checks whether skill-assisted execution avoids unsafe behavior such as secret leakage, destructive commands, or unauthorized access. <br>
- Correctness: Checks whether the agent follows the expected workflow and produces the correct final output. <br>
- Discoverability: Checks whether the agent loads the skill when relevant and avoids using it when irrelevant. <br>
- Effectiveness: Checks whether the agent performs measurably better with the skill than without it. <br>
- Efficiency: Checks whether the agent uses fewer tokens and avoids redundant work. <br>



## Skill Version(s): <br>
63e8ce51 (source: git SHA, committed 2026-06-25) <br>

## Ethical Considerations: <br>
NVIDIA believes Trustworthy AI is a shared responsibility and we have established policies and practices to enable development for a wide array of AI applications. When downloaded or used in accordance with our terms of service, developers should work with their internal team to ensure this skill meets requirements for the relevant industry and use case and addresses unforeseen product misuse. <br>

(For Release on NVIDIA Platforms Only) <br>
Please report quality, risk, security vulnerabilities or NVIDIA AI Concerns [here](https://app.intigriti.com/programs/nvidia/nvidiavdp/detail). <br>
