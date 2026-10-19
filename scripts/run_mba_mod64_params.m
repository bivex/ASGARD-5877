% =========================================================================
% ASGARD-5877: runner for the Z_{2^64} modular parameter generator.
% GNU Octave / MATLAB compatible (no toolbox required).
%
%   octave scripts/run_mba_mod64_params.m
%   matlab -batch "run('scripts/run_mba_mod64_params.m')"
% =========================================================================

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);
mba_mod64_params();
