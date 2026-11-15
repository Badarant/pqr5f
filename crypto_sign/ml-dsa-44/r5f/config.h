#ifndef CONFIG_H
#define CONFIG_H

/*
 * pqr5f: DILITHIUM_MODE can be overridden from the command line
 * (-DDILITHIUM_MODE=3 / =5), so this single directory builds all three
 * parameter sets. pqm4 instead has ml-dsa-65 and ml-dsa-87 directories of
 * symbolic links into this one, which a Windows checkout does not
 * materialise.
 */
#ifndef DILITHIUM_MODE
#define DILITHIUM_MODE 2
#endif
// #define SIGN_STACKSTRATEGY 2

#endif
