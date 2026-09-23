#!/usr/bin/env bash
# Generate Network Operator YAML for every customer platform configuration.

set -euo pipefail

readonly REPO_DIR="${NETOP_REPO_DIR:-${HOME}/netop-tools}"
readonly CONFIG_LINK="${REPO_DIR}/global_ops_user.cfg"
readonly UC_LINK="${REPO_DIR}/uc"
readonly CUSTOMERS_DIR="${REPO_DIR}/customers"
readonly -a PLATFORMS=(dell hpe lenovo oci pdx rtxpro smc trinity)

if [[ ! -f "${REPO_DIR}/NETOP_ROOT_DIR.sh" ]]; then
    echo "ERROR: netop-tools was not found at ${REPO_DIR}" >&2
    echo "Set NETOP_REPO_DIR to use a different checkout." >&2
    exit 1
fi

state_dir=$(mktemp -d)
config_existed=false
uc_existed=false

if [[ -e "${CONFIG_LINK}" || -L "${CONFIG_LINK}" ]]; then
    cp -a -- "${CONFIG_LINK}" "${state_dir}/global_ops_user.cfg"
    config_existed=true
fi
if [[ -e "${UC_LINK}" || -L "${UC_LINK}" ]]; then
    cp -a -- "${UC_LINK}" "${state_dir}/uc"
    uc_existed=true
fi

restore_state() {
    rm -f -- "${CONFIG_LINK}" "${UC_LINK}"
    if [[ "${config_existed}" == true ]]; then
        cp -a -- "${state_dir}/global_ops_user.cfg" "${CONFIG_LINK}"
    fi
    if [[ "${uc_existed}" == true ]]; then
        cp -a -- "${state_dir}/uc" "${UC_LINK}"
    fi
    rm -rf -- "${state_dir}"
}
trap restore_state EXIT

cd "${REPO_DIR}"
# NETOP_ROOT_DIR.sh intentionally derives NETOP_ROOT_DIR from the current directory.
# shellcheck disable=SC1091
source ./NETOP_ROOT_DIR.sh

# Ensure global_ops.cfg follows the symlink managed by this script rather than a
# GLOBAL_OPS_USER value inherited from the caller.
unset GLOBAL_OPS_USER

generated_count=0
shopt -s nullglob

for platform in "${PLATFORMS[@]}"; do
    platform_dir="${NETOP_ROOT_DIR}/config/${platform}"
    if [[ ! -d "${platform_dir}" ]]; then
        echo "WARNING: Skipping missing platform directory: ${platform_dir}" >&2
        continue
    fi

    configs=("${platform_dir}"/global_ops_user*)
    if (( ${#configs[@]} == 0 )); then
        echo "WARNING: No global_ops_user* files found in ${platform_dir}" >&2
        continue
    fi

    for config_file in "${configs[@]}"; do
        [[ -f "${config_file}" ]] || continue

        config_name=$(basename "${config_file}")
        variant=${config_name#global_ops_user.cfg}
        variant=${variant#.}
        variant=${variant:-default}
        destination="${CUSTOMERS_DIR}/${platform}/${variant}"

        echo "Generating ${platform}/${variant} from ${config_file}"
        rm -f -- "${CONFIG_LINK}"
        ln -s -- "${config_file}" "${CONFIG_LINK}"

        cd "${NETOP_ROOT_DIR}"
        ./setuc.sh
        cd ./uc
        rm -f -- ./*.yaml
        "${NETOP_ROOT_DIR}/ops/mk-config.sh"

        generated_yaml=(./*.yaml)
        if (( ${#generated_yaml[@]} == 0 )); then
            echo "ERROR: No YAML was generated for ${config_file}" >&2
            exit 1
        fi

        mkdir -p -- "${destination}"
        rm -f -- "${destination}"/*.yaml
        cp -- "${generated_yaml[@]}" "${destination}/"
        ((generated_count += 1))
    done
done

echo "Generated ${generated_count} configuration set(s) under ${CUSTOMERS_DIR}"
