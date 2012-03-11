function [fcomp] = qsubcompile(fname, varargin)

% QSUBCOMPILE compiles your function into an standalone executable
% that can easily be distributed on a cluster by QSUBCELLFUN.
% Running a compiled version of your function does not take any
% additional MATLAB licenses. Note that it does require that the
% matching run-time environment is installed on your cluster.
%
% Use as
%   compiledfun = qsubcompile(fname)
%   argout      = qsubcellfun(compiledfun, argin, ...)
% or
%   compiledfun = qsubcompile(fname)
%   jobid       = qsubfeval(compiledfun, argin, ...)
%   argout      = qsubget(jobid)
%
% Optional input arguments should be specified in key-value pairs
% and can include
%   batchid        = string that is used for the compiled application
%                    filename and to identify the jobs in the queue, the
%                    default is automatically determined and looks
%                    like user_host_pid_batch.
%   toolbox        = string or cell-array with strings, non-standard
%                    Mathworks toolboxes to include (see below).
%
% When executing a single batch of jobs using QSUBCELLFUN, you can also
% compile your function on the fly with the compile flag like this
%   argout      = qsubcellfun(fname, argin, ..., 'compile', 'yes')
% Using this syntax, the compiled function will be automatically cleaned
% up immediately after execution.
%
% If you need to include additional functions that are not automatically
% detected as dependencies by the MATLAB compiler, e.g. because using
% constructs like feval(sprintf(...)), you can specify fname as a
% cell-array. For example
%   compiledfun = qsubcompile({@ft_definetrial, @trialfun_custom})
%
% If you need to include Mathworks toolboxes that are not automatically
% detected as dependencies by the MATLAB compiler, you can specify them
% likt this
%   compiledfun = qsubcompile(fname, 'toolbox', {'signal', 'image', 'stats'})
%
% A common problem for compilation is caused by the use of addpath in
% your startup.m file. Please change your startup.m file into
%   if ~isdeployed
%    % here goes the original content of your startup file
%    % ...
%   end
%
% See also QSUBCELLFUN, QSUBFEVAL, MCC, ISDEPLOYED

% -----------------------------------------------------------------------
% Copyright (C) 2012, Robert Oostenveld
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/
% -----------------------------------------------------------------------

% Note that the function will be wrapped into qsubexec, which takes care of
% the loading and saving of the input and output arguments.

% It is possible for the user to have multiple MATLAB sessions running at
% the same time (on the same or different computers) and to start multiple
% instances of qsubcellfun. To ensure that those do not interfere with each
% others, each batch of jobs (i.e. instance of qsubcellfun) should get a
% unique identifier that is used in the filename of the temporary mat files.

% get the optional input arguments
batch   = ft_getopt(varargin, 'batch',   getbatch());               % this is a number that is automatically incremented
batchid = ft_getopt(varargin, 'batchid', generatebatchid(batch));   % this is a string like user_host_pid_batch
toolbox = ft_getopt(varargin, 'toolbox', {});

if ischar(toolbox)
  % this should be a cell-array with strings
  toolbox = {toolbox};
end

% some temporary filse are made during compilation, these flags determine
% whether they can be cleaned up afterwards
hasreadme = exist('./readme.txt', 'file');
hasmcclog = exist('./mccExcludedFiles.log', 'file');

if iscell(fname)
  fdeps = fname(2:end);  % this remains a cell-array
  fname = fname{1};      % this is a handle or string
else
  fdeps = {};
end

if isa(fname, 'function_handle')
  % convert the function handle back into a string (e.g. @plus should be 'plus')
  fname = func2str(fname);
end

for i=1:length(fdeps)
  if isa(fdeps{i}, 'function_handle')
    fdeps{i} = func2str(fdeps{i});
  end
end

if ~isempty(toolbox)
  % each toolbox should be added to the mcc command line as -p <full_path>
  toolboxopt = cell(1,length(toolbox));
  for i=1:length(toolbox)
    % find the directory where the toolbox is to be found
    toolboxpath = fileparts(which(fullfile(toolbox{i}, 'Contents.m')));
    if isempty(toolboxpath)
      error('the Mathworks toolbox "%s" could not be found', toolbox{i});
    else
      fprintf('including %s\n', toolboxpath);
    end
    toolboxopt{2*(i-1)+1} = '-p';
    toolboxopt{2*(i-1)+2} = toolboxpath;
  end
else
  toolboxopt = {};
end

fprintf('compiling %s into %s\n', fname, batchid);
% try to compile into a stand-allone application
% ensure that cellfun is included, it might be needed for stacked jobs
mcc('-N', '-R', '-nodisplay', '-o', batchid, toolboxopt{:}, '-m', 'qsubexec', 'cellfun', fname, fdeps{:});
fprintf('finished compiling\n');

if ~hasreadme
  delete('./readme.txt');
end

if ~hasmcclog
  delete('./mccExcludedFiles.log');
end

% reemmber all details
fcomp.fname       = fname;
fcomp.fdeps       = fdeps;
fcomp.batch       = batch;
fcomp.batchid     = batchid;
fcomp.executable  = fullfile(pwd, sprintf('run_%s.sh', batchid));
