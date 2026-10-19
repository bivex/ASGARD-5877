% =========================================================================
% ASGARD-5877: runner for the pipeline phase compatibility audit.
% GNU Octave / MATLAB compatible (no toolbox required).
%
%   octave scripts/run_pipeline_compat.m
%   matlab -batch "run('scripts/run_pipeline_compat.m')"
%
% Optional: pass a directory with phase dumps and the verbosity mode.
%   octave --eval "addpath('scripts'); pipeline_compat('binaries/pipeline_dump','verbose')"
% =========================================================================

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

json_dir = 'binaries/pipeline_dump';
if numel(argv()) >= 1
  json_dir = argv(){1};
end
mode = '';
if numel(argv()) >= 2
  mode = argv(){2};
end

if isempty(mode)
  pipeline_compat(json_dir);
else
  pipeline_compat(json_dir, mode);
end
