/* =====================================================================
 * mpiprof.c -- mini profileur MPI "maison" (interface PMPI)
 * =====================================================================
 * Principe (standard MPI, section "profiling interface") :
 *   chaque fonction MPI_Xxx existe aussi sous le nom PMPI_Xxx.
 *   Si on fournit notre propre MPI_Xxx, le programme appelle la notre ;
 *   elle demarre un chrono, appelle la vraie PMPI_Xxx, arrete le chrono,
 *   et ajoute 1 au compteur de Xxx.
 *
 * Utilisation : on compile en bibliotheque partagee puis
 *     mpirun ... -x LD_PRELOAD=/chemin/libmpiprof.so ./appli
 *   (ou export LD_PRELOAD avant srun). Aucune recompilation de l'appli.
 *
 * Sortie : au MPI_Finalize, chaque rang ecrit
 *     $MPIPROF_DIR/rank_<r>.txt   (MPIPROF_DIR par defaut : ./mpiprof)
 *   avec une ligne par fonction : nom  nb_appels  temps_total_s
 *   + la duree totale du programme (MPI_Init -> MPI_Finalize).
 *   Le script mpiprof_report.py fait la synthese (top 3).
 *
 * Limites (a dire a l'oral si on demande) :
 *   - seules les fonctions listees ci-dessous sont comptees ;
 *   - les appels faits depuis du Fortran (ELPA dans OpenMX) peuvent
 *     ne pas passer par ces wrappers C selon l'implementation MPI.
 * ===================================================================== */
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* ---- liste des fonctions suivies (l'ordre definit les indices) ---- */
enum {
    F_Send, F_Recv, F_Isend, F_Irecv, F_Ssend, F_Issend, F_Sendrecv,
    F_Wait, F_Waitall, F_Waitany, F_Waitsome, F_Test, F_Testall, F_Testany,
    F_Probe, F_Iprobe,
    F_Barrier, F_Bcast, F_Reduce, F_Allreduce, F_Gather, F_Gatherv,
    F_Allgather, F_Allgatherv, F_Scatter, F_Scatterv, F_Alltoall, F_Alltoallv,
    F_Reduce_scatter, F_Iallreduce, F_Ibcast, F_Ibarrier,
    F_Comm_split, F_Comm_dup, F_Comm_split_type,
    F_File_open, F_File_read_at, F_File_read_at_all, F_File_read_all,
    F_File_write_at, F_File_write_at_all, F_File_write_all,
    F_Win_fence, F_Put, F_Get,
    NFUNC
};
static const char *names[NFUNC] = {
    "MPI_Send", "MPI_Recv", "MPI_Isend", "MPI_Irecv", "MPI_Ssend", "MPI_Issend", "MPI_Sendrecv",
    "MPI_Wait", "MPI_Waitall", "MPI_Waitany", "MPI_Waitsome", "MPI_Test", "MPI_Testall", "MPI_Testany",
    "MPI_Probe", "MPI_Iprobe",
    "MPI_Barrier", "MPI_Bcast", "MPI_Reduce", "MPI_Allreduce", "MPI_Gather", "MPI_Gatherv",
    "MPI_Allgather", "MPI_Allgatherv", "MPI_Scatter", "MPI_Scatterv", "MPI_Alltoall", "MPI_Alltoallv",
    "MPI_Reduce_scatter", "MPI_Iallreduce", "MPI_Ibcast", "MPI_Ibarrier",
    "MPI_Comm_split", "MPI_Comm_dup", "MPI_Comm_split_type",
    "MPI_File_open", "MPI_File_read_at", "MPI_File_read_at_all", "MPI_File_read_all",
    "MPI_File_write_at", "MPI_File_write_at_all", "MPI_File_write_all",
    "MPI_Win_fence", "MPI_Put", "MPI_Get"
};

static long long ncalls[NFUNC];
static double    tcalls[NFUNC];
static double    t_init = 0.0;

/* Chrono autour de l'appel reel : "call" est l'appel PMPI complet. */
#define TIMED(idx, call)                         \
    do {                                         \
        double t0_ = PMPI_Wtime();               \
        int rc_ = (call);                        \
        tcalls[idx] += PMPI_Wtime() - t0_;       \
        ncalls[idx]++;                           \
        return rc_;                              \
    } while (0)

/* ---------------- initialisation / fin ---------------- */
int MPI_Init(int *argc, char ***argv) {
    int rc = PMPI_Init(argc, argv);
    t_init = PMPI_Wtime();
    return rc;
}
int MPI_Init_thread(int *argc, char ***argv, int req, int *prov) {
    int rc = PMPI_Init_thread(argc, argv, req, prov);
    t_init = PMPI_Wtime();
    return rc;
}

int MPI_Finalize(void) {
    int rank = 0, size = 1;
    double total = PMPI_Wtime() - t_init;
    PMPI_Comm_rank(MPI_COMM_WORLD, &rank);
    PMPI_Comm_size(MPI_COMM_WORLD, &size);

    const char *dir = getenv("MPIPROF_DIR");
    if (dir == NULL) dir = "mpiprof";
    mkdir(dir, 0755);                 /* echoue sans gravite s'il existe deja */

    char path[1024];
    snprintf(path, sizeof(path), "%s/rank_%05d.txt", dir, rank);
    FILE *f = fopen(path, "w");
    if (f != NULL) {
        char host[MPI_MAX_PROCESSOR_NAME]; int len;
        PMPI_Get_processor_name(host, &len);
        fprintf(f, "# rank %d size %d host %s app_time_s %.6f\n", rank, size, host, total);
        for (int i = 0; i < NFUNC; i++)
            if (ncalls[i] > 0)
                fprintf(f, "%s %lld %.6f\n", names[i], ncalls[i], tcalls[i]);
        fclose(f);
    }
    return PMPI_Finalize();
}

/* ---------------- point a point ---------------- */
int MPI_Send(const void *b, int c, MPI_Datatype d, int dst, int tag, MPI_Comm cm)
{ TIMED(F_Send, PMPI_Send(b, c, d, dst, tag, cm)); }
int MPI_Recv(void *b, int c, MPI_Datatype d, int src, int tag, MPI_Comm cm, MPI_Status *s)
{ TIMED(F_Recv, PMPI_Recv(b, c, d, src, tag, cm, s)); }
int MPI_Isend(const void *b, int c, MPI_Datatype d, int dst, int tag, MPI_Comm cm, MPI_Request *r)
{ TIMED(F_Isend, PMPI_Isend(b, c, d, dst, tag, cm, r)); }
int MPI_Irecv(void *b, int c, MPI_Datatype d, int src, int tag, MPI_Comm cm, MPI_Request *r)
{ TIMED(F_Irecv, PMPI_Irecv(b, c, d, src, tag, cm, r)); }
int MPI_Ssend(const void *b, int c, MPI_Datatype d, int dst, int tag, MPI_Comm cm)
{ TIMED(F_Ssend, PMPI_Ssend(b, c, d, dst, tag, cm)); }
int MPI_Issend(const void *b, int c, MPI_Datatype d, int dst, int tag, MPI_Comm cm, MPI_Request *r)
{ TIMED(F_Issend, PMPI_Issend(b, c, d, dst, tag, cm, r)); }
int MPI_Sendrecv(const void *sb, int sc, MPI_Datatype sd, int dst, int st,
                 void *rb, int rc, MPI_Datatype rd, int src, int rt, MPI_Comm cm, MPI_Status *s)
{ TIMED(F_Sendrecv, PMPI_Sendrecv(sb, sc, sd, dst, st, rb, rc, rd, src, rt, cm, s)); }

int MPI_Wait(MPI_Request *r, MPI_Status *s)
{ TIMED(F_Wait, PMPI_Wait(r, s)); }
int MPI_Waitall(int n, MPI_Request r[], MPI_Status s[])
{ TIMED(F_Waitall, PMPI_Waitall(n, r, s)); }
int MPI_Waitany(int n, MPI_Request r[], int *i, MPI_Status *s)
{ TIMED(F_Waitany, PMPI_Waitany(n, r, i, s)); }
int MPI_Waitsome(int n, MPI_Request r[], int *o, int idx[], MPI_Status s[])
{ TIMED(F_Waitsome, PMPI_Waitsome(n, r, o, idx, s)); }
int MPI_Test(MPI_Request *r, int *fl, MPI_Status *s)
{ TIMED(F_Test, PMPI_Test(r, fl, s)); }
int MPI_Testall(int n, MPI_Request r[], int *fl, MPI_Status s[])
{ TIMED(F_Testall, PMPI_Testall(n, r, fl, s)); }
int MPI_Testany(int n, MPI_Request r[], int *i, int *fl, MPI_Status *s)
{ TIMED(F_Testany, PMPI_Testany(n, r, i, fl, s)); }
int MPI_Probe(int src, int tag, MPI_Comm cm, MPI_Status *s)
{ TIMED(F_Probe, PMPI_Probe(src, tag, cm, s)); }
int MPI_Iprobe(int src, int tag, MPI_Comm cm, int *fl, MPI_Status *s)
{ TIMED(F_Iprobe, PMPI_Iprobe(src, tag, cm, fl, s)); }

/* ---------------- collectives ---------------- */
int MPI_Barrier(MPI_Comm cm)
{ TIMED(F_Barrier, PMPI_Barrier(cm)); }
int MPI_Bcast(void *b, int c, MPI_Datatype d, int root, MPI_Comm cm)
{ TIMED(F_Bcast, PMPI_Bcast(b, c, d, root, cm)); }
int MPI_Reduce(const void *sb, void *rb, int c, MPI_Datatype d, MPI_Op op, int root, MPI_Comm cm)
{ TIMED(F_Reduce, PMPI_Reduce(sb, rb, c, d, op, root, cm)); }
int MPI_Allreduce(const void *sb, void *rb, int c, MPI_Datatype d, MPI_Op op, MPI_Comm cm)
{ TIMED(F_Allreduce, PMPI_Allreduce(sb, rb, c, d, op, cm)); }
int MPI_Gather(const void *sb, int sc, MPI_Datatype sd, void *rb, int rc, MPI_Datatype rd, int root, MPI_Comm cm)
{ TIMED(F_Gather, PMPI_Gather(sb, sc, sd, rb, rc, rd, root, cm)); }
int MPI_Gatherv(const void *sb, int sc, MPI_Datatype sd, void *rb, const int rcs[], const int dis[],
                MPI_Datatype rd, int root, MPI_Comm cm)
{ TIMED(F_Gatherv, PMPI_Gatherv(sb, sc, sd, rb, rcs, dis, rd, root, cm)); }
int MPI_Allgather(const void *sb, int sc, MPI_Datatype sd, void *rb, int rc, MPI_Datatype rd, MPI_Comm cm)
{ TIMED(F_Allgather, PMPI_Allgather(sb, sc, sd, rb, rc, rd, cm)); }
int MPI_Allgatherv(const void *sb, int sc, MPI_Datatype sd, void *rb, const int rcs[], const int dis[],
                   MPI_Datatype rd, MPI_Comm cm)
{ TIMED(F_Allgatherv, PMPI_Allgatherv(sb, sc, sd, rb, rcs, dis, rd, cm)); }
int MPI_Scatter(const void *sb, int sc, MPI_Datatype sd, void *rb, int rc, MPI_Datatype rd, int root, MPI_Comm cm)
{ TIMED(F_Scatter, PMPI_Scatter(sb, sc, sd, rb, rc, rd, root, cm)); }
int MPI_Scatterv(const void *sb, const int scs[], const int dis[], MPI_Datatype sd, void *rb, int rc,
                 MPI_Datatype rd, int root, MPI_Comm cm)
{ TIMED(F_Scatterv, PMPI_Scatterv(sb, scs, dis, sd, rb, rc, rd, root, cm)); }
int MPI_Alltoall(const void *sb, int sc, MPI_Datatype sd, void *rb, int rc, MPI_Datatype rd, MPI_Comm cm)
{ TIMED(F_Alltoall, PMPI_Alltoall(sb, sc, sd, rb, rc, rd, cm)); }
int MPI_Alltoallv(const void *sb, const int scs[], const int sdis[], MPI_Datatype sd,
                  void *rb, const int rcs[], const int rdis[], MPI_Datatype rd, MPI_Comm cm)
{ TIMED(F_Alltoallv, PMPI_Alltoallv(sb, scs, sdis, sd, rb, rcs, rdis, rd, cm)); }
int MPI_Reduce_scatter(const void *sb, void *rb, const int rcs[], MPI_Datatype d, MPI_Op op, MPI_Comm cm)
{ TIMED(F_Reduce_scatter, PMPI_Reduce_scatter(sb, rb, rcs, d, op, cm)); }
int MPI_Iallreduce(const void *sb, void *rb, int c, MPI_Datatype d, MPI_Op op, MPI_Comm cm, MPI_Request *r)
{ TIMED(F_Iallreduce, PMPI_Iallreduce(sb, rb, c, d, op, cm, r)); }
int MPI_Ibcast(void *b, int c, MPI_Datatype d, int root, MPI_Comm cm, MPI_Request *r)
{ TIMED(F_Ibcast, PMPI_Ibcast(b, c, d, root, cm, r)); }
int MPI_Ibarrier(MPI_Comm cm, MPI_Request *r)
{ TIMED(F_Ibarrier, PMPI_Ibarrier(cm, r)); }

/* ---------------- communicateurs ---------------- */
int MPI_Comm_split(MPI_Comm cm, int color, int key, MPI_Comm *nc)
{ TIMED(F_Comm_split, PMPI_Comm_split(cm, color, key, nc)); }
int MPI_Comm_dup(MPI_Comm cm, MPI_Comm *nc)
{ TIMED(F_Comm_dup, PMPI_Comm_dup(cm, nc)); }
int MPI_Comm_split_type(MPI_Comm cm, int type, int key, MPI_Info info, MPI_Comm *nc)
{ TIMED(F_Comm_split_type, PMPI_Comm_split_type(cm, type, key, info, nc)); }

/* ---------------- MPI-IO (lecture de la geometrie HemeLB, ecritures) ---------------- */
int MPI_File_open(MPI_Comm cm, const char *fn, int amode, MPI_Info info, MPI_File *fh)
{ TIMED(F_File_open, PMPI_File_open(cm, fn, amode, info, fh)); }
int MPI_File_read_at(MPI_File fh, MPI_Offset off, void *b, int c, MPI_Datatype d, MPI_Status *s)
{ TIMED(F_File_read_at, PMPI_File_read_at(fh, off, b, c, d, s)); }
int MPI_File_read_at_all(MPI_File fh, MPI_Offset off, void *b, int c, MPI_Datatype d, MPI_Status *s)
{ TIMED(F_File_read_at_all, PMPI_File_read_at_all(fh, off, b, c, d, s)); }
int MPI_File_read_all(MPI_File fh, void *b, int c, MPI_Datatype d, MPI_Status *s)
{ TIMED(F_File_read_all, PMPI_File_read_all(fh, b, c, d, s)); }
int MPI_File_write_at(MPI_File fh, MPI_Offset off, const void *b, int c, MPI_Datatype d, MPI_Status *s)
{ TIMED(F_File_write_at, PMPI_File_write_at(fh, off, b, c, d, s)); }
int MPI_File_write_at_all(MPI_File fh, MPI_Offset off, const void *b, int c, MPI_Datatype d, MPI_Status *s)
{ TIMED(F_File_write_at_all, PMPI_File_write_at_all(fh, off, b, c, d, s)); }
int MPI_File_write_all(MPI_File fh, const void *b, int c, MPI_Datatype d, MPI_Status *s)
{ TIMED(F_File_write_all, PMPI_File_write_all(fh, b, c, d, s)); }

/* ---------------- one-sided ---------------- */
int MPI_Win_fence(int assert_, MPI_Win w)
{ TIMED(F_Win_fence, PMPI_Win_fence(assert_, w)); }
int MPI_Put(const void *ob, int oc, MPI_Datatype od, int tr, MPI_Aint td, int tc, MPI_Datatype tdt, MPI_Win w)
{ TIMED(F_Put, PMPI_Put(ob, oc, od, tr, td, tc, tdt, w)); }
int MPI_Get(void *ob, int oc, MPI_Datatype od, int tr, MPI_Aint td, int tc, MPI_Datatype tdt, MPI_Win w)
{ TIMED(F_Get, PMPI_Get(ob, oc, od, tr, td, tc, tdt, w)); }
