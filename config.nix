{ ... }@args:
let 
  share = a: b: builtins.floor (a * b);
  toAllowedCpus = x: "0-${toString x}";
in
{
  profiles = {
      allCores   = { AllowedCPUs = toAllowedCpus (args.nproc - 1); };
      browsing    = { AllowedCPUs = toAllowedCpus (share args.nproc 0.5); };
      work        = { AllowedCPUs = toAllowedCpus (share args.nproc 0.5); };
      gaming      = { AllowedCPUs = toAllowedCpus (share args.nproc 0.2); };
    };
}
