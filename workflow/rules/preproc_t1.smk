ruleorder:  compose_template_xfm_corobl > convert_template_xfm_ras2itk


#just grab the first T1w for now:
rule import_t1:
    input: lambda wildcards: expand(config['input_path']['T1w'],zip,**snakebids.filter_list(config['input_zip_lists']['T1w'],wildcards))[0]
    output: bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='T1w.nii.gz')
    group: 'subj'
    shell: 'cp {input} {output}'

rule n4_t1:
    input: 
        t1 = bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='T1w.nii.gz'),
    output:
        t1 = bids(root='work',datatype='anat',**config['subj_wildcards'],desc='n4', suffix='T1w.nii.gz'),
    threads: 8
    container: config['singularity']['prepdwi']
    group: 'subj'
    shell:
        'ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS={threads} '
        'N4BiasFieldCorrection -d 3 -i {input.t1} -o {output}'



rule affine_aladin:
    input: 
        flo = bids(root='work',datatype='anat',**config['subj_wildcards'],desc='n4',suffix='T1w.nii.gz'),
        ref = os.path.join(config['snakemake_dir'],config['template_files'][config['template']]['T1w']),
    output: 
        warped_subj = bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='T1w.nii.gz',space=config['template'],desc='affine'),
        xfm_ras = bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='xfm.txt',from_='T1w',to=config['template'],desc='affine',type_='ras'),
    container: config['singularity']['prepdwi']
    group: 'subj'
    shell:
        'reg_aladin -flo {input.flo} -ref {input.ref} -res {output.warped_subj} -aff {output.xfm_ras}'



rule convert_template_xfm_ras2itk:
    input:
        bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='xfm.txt',from_='T1w',to=config['template'],desc='affine',type_='ras'),
    output:
        bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='xfm.txt',from_='T1w',to=config['template'],desc='affine',type_='itk'),
    container: config['singularity']['prepdwi']
    group: 'subj'
    shell:
        'c3d_affine_tool {input}  -oitk {output}'


#now have subject -> template transform, can compose that with template -> corobl to get subject -> corobl
rule compose_template_xfm_corobl:
    input:
        sub_to_std = bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='xfm.txt',from_='T1w',to=config['template'],desc='affine',type_='itk'),
        std_to_cor = os.path.join(config['snakemake_dir'],config['template_files'][config['template']]['xfm_corobl'])
    output:
        sub_to_cor = bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='xfm.txt',from_='T1w',to='corobl',desc='affine',type_='itk'),
    container: config['singularity']['prepdwi']
    group: 'subj'
    shell:
        'c3d_affine_tool -itk {input.sub_to_std} -itk {input.std_to_cor} -mult -oitk {output}'

rule invert_template_xfm_itk2ras:
    input:
        xfm_ras = bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='xfm.txt',from_='T1w',to='corobl',desc='affine',type_='itk'),
    output:
        xfm_ras = bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='xfm.txt',from_='T1w',to='corobl',desc='affineInverse',type_='ras'),
    container: config['singularity']['prepdwi']
    group: 'subj'
    shell:
        'c3d_affine_tool -itk {input} -inv -o {output}'


#create inverted T1w image (to fool autotop trained on T2w):
rule invert_t1w_intensity:
    input:
        t1 = bids(root='work',datatype='anat',**config['subj_wildcards'],desc='n4', suffix='T1w.nii.gz'),
    output:
        t1 = bids(root='work',datatype='anat',**config['subj_wildcards'],desc='n4', suffix='InvT1w.nii.gz'),
    container: config['singularity']['prepdwi']
    group: 'subj'
    shell: 'c3d {input}  -scale -1 -stretch 0% 100% 0 1000 -o {output}'

#apply transform to get subject in corobl cropped space
rule warp_t1_to_corobl_crop:
    input:
        t1 = bids(root='work',datatype='anat',**config['subj_wildcards'],desc='n4', suffix='InvT1w.nii.gz'),
        xfm = bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='xfm.txt',from_='T1w',to='corobl',desc='affine',type_='itk'),
        ref = os.path.join(config['snakemake_dir'],config['template_files'][config['template']]['crop_ref']),
        std_to_cor = os.path.join(config['snakemake_dir'],config['template_files'][config['template']]['xfm_corobl'])
    output: 
        t1 = bids(root='work',datatype='anat',**config['subj_wildcards'],desc='cropped', suffix='InvT1w.nii.gz',space='corobl',hemi='{hemi,L|R}'),
    container: config['singularity']['prepdwi']
    group: 'subj'
    shell:
        'ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS={threads} '
        'antsApplyTransforms -d 3 --interpolation Linear -i {input.t1} -o {output.t1} -r {input.ref}  -t {input.xfm}' 


rule lr_flip_t1:
    input:
        nii = bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='InvT1w.nii.gz',desc='cropped',space='corobl',hemi='{hemi}'),
    output:
        nii = bids(root='work',datatype='anat',**config['subj_wildcards'],suffix='InvT1w.nii.gz',desc='cropped',space='corobl',hemi='{hemi,L}flip'),
    container: config['singularity']['prepdwi']
    group: 'subj'
    shell:
        'c3d {input} -flip x -o  {output}'



