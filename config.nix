{ ... }@args:
let 
  div = a: b: builtins.floor (a * 1.0 / b);
  share = a: b: builtins.floor (a * b);
  toAllowedCpus = x: "0-${x}";
in
{
  profiles = {
      all-cores   = { AllowedCPUs = toAllowedCpus args.nproc; };
      browsing    = { AllowedCPUs = toAllowedCpus (share args.nproc 0.5); };
      work        = { AllowedCPUs = toAllowedCpus (share args.nproc 0.5); };
      gaming      = { AllowedCPUs = toAllowedCpus (share args.nproc 0.2); };
    };
}
